extends Node
class_name EconomyManager

const START_MONEY := 800
const MAX_MONEY := 16000
const WIN_REWARD := 3250
const LOSS_BASE := 1400
const LOSS_INCREMENT := 500
const LOSS_MAX := 3400
const PLANT_BONUS := 300
const KEVLAR_PRICE := 650
const DEFUSE_KIT_PRICE := 400
const FLASH_PRICE := 200
const FLASH_MAX := 2
const SMOKE_PRICE := 300
const SMOKE_MAX := 1

# peer_id -> money (server-authoritative)
var _money: Dictionary = {}
# peer_id -> loss streak count
var _loss_streak: Dictionary = {}

var team_manager: TeamManager
var round_manager: RoundManager

func _ready():
	team_manager = $"../TeamManager"
	round_manager = $"../RoundManager"

	if round_manager:
		round_manager.player_killed.connect(_on_player_killed)
		round_manager.round_ended.connect(_on_round_ended)

	var bomb_node := get_tree().current_scene.get_node_or_null("Network/Bomb") as Bomb
	if bomb_node:
		bomb_node.bomb_planted.connect(_on_bomb_planted.bind(bomb_node))

func init_player(peer_id: int):
	_money[peer_id] = START_MONEY
	_loss_streak[peer_id] = 0
	if multiplayer.is_server():
		_sync_money.rpc_id(peer_id, START_MONEY)

func get_money(peer_id: int) -> int:
	return _money.get(peer_id, 0)

func add_money(peer_id: int, amount: int):
	if not multiplayer.is_server():
		return
	_money[peer_id] = clampi(_money.get(peer_id, 0) + amount, 0, MAX_MONEY)
	_sync_money.rpc_id(peer_id, _money[peer_id])

func try_buy_weapon(peer_id: int, weapon_id: int, avatar: CharacterBody3D) -> bool:
	if not multiplayer.is_server():
		return false

	var weapon := WeaponRegistry.get_weapon(weapon_id)
	if weapon == null:
		return false

	# Must be alive
	if avatar.is_dead:
		return false

	# Must be in freeze time
	if round_manager.state != RoundManager.RoundState.FREEZE_TIME:
		return false
	if NetworkTime.tick >= round_manager.freeze_end_tick:
		return false

	# Team restriction
	if weapon.team >= 0:
		var player_team := team_manager.get_team(peer_id)
		if player_team != weapon.team:
			return false

	# Price check
	var money := get_money(peer_id)
	if money < weapon.price:
		return false

	# Already have same weapon = denied
	var wm: WeaponManager = avatar.weapon_manager
	if wm.inventory[weapon.slot] == weapon_id:
		return false

	# Buy: deduct money, give weapon
	add_money(peer_id, -weapon.price)
	wm.give_weapon(weapon_id)
	return true

func try_buy_kevlar(peer_id: int, avatar: CharacterBody3D) -> bool:
	if not multiplayer.is_server():
		return false

	if avatar.is_dead:
		return false

	if round_manager.state != RoundManager.RoundState.FREEZE_TIME:
		return false
	if NetworkTime.tick >= round_manager.freeze_end_tick:
		return false

	if avatar.armor >= 100:
		return false

	var money := get_money(peer_id)
	if money < KEVLAR_PRICE:
		return false

	add_money(peer_id, -KEVLAR_PRICE)
	avatar.armor = 100
	return true

func try_buy_defuse_kit(peer_id: int, avatar: CharacterBody3D) -> bool:
	if not multiplayer.is_server():
		return false

	if avatar.is_dead:
		return false

	if round_manager.state != RoundManager.RoundState.FREEZE_TIME:
		return false
	if NetworkTime.tick >= round_manager.freeze_end_tick:
		return false

	# Only CTs
	if team_manager.get_team(peer_id) != TeamManager.Team.CT:
		return false

	if avatar.has_defuse_kit:
		return false

	var money := get_money(peer_id)
	if money < DEFUSE_KIT_PRICE:
		return false

	add_money(peer_id, -DEFUSE_KIT_PRICE)
	avatar.has_defuse_kit = true
	return true

func try_buy_grenade(peer_id: int, grenade_type: int, avatar: CharacterBody3D) -> bool:
	## grenade_type: 0=flash, 1=smoke
	if not multiplayer.is_server():
		return false

	if avatar.is_dead:
		return false

	if round_manager.state != RoundManager.RoundState.FREEZE_TIME:
		return false
	if NetworkTime.tick >= round_manager.freeze_end_tick:
		return false

	var price := FLASH_PRICE if grenade_type == 0 else SMOKE_PRICE
	var money := get_money(peer_id)
	if money < price:
		return false

	var wm: WeaponManager = avatar.weapon_manager
	if not wm.add_grenade(grenade_type):
		return false  # at max

	add_money(peer_id, -price)
	return true

func _on_bomb_planted(_site_name: String, bomb_node: Bomb):
	if not multiplayer.is_server():
		return
	# Plant bonus: all Ts get $300
	for peer_id in team_manager.get_team_members(TeamManager.Team.T):
		add_money(peer_id, PLANT_BONUS)

func _on_player_killed(victim_id: int, killer_id: int, weapon_id: int, _kill_tick: int):
	if not multiplayer.is_server():
		return
	if killer_id < 0:
		return
	var weapon := WeaponRegistry.get_weapon(weapon_id)
	var reward := weapon.kill_reward if weapon else 300
	add_money(killer_id, reward)

func _on_round_ended(winner: TeamManager.Team):
	if not multiplayer.is_server():
		return

	for peer_id in team_manager.assignments:
		var team := team_manager.get_team(peer_id)
		if team == TeamManager.Team.NONE:
			continue

		if team == winner:
			add_money(peer_id, WIN_REWARD)
			_loss_streak[peer_id] = 0
		else:
			var streak: int = _loss_streak.get(peer_id, 0)
			var loss_reward: int = mini(LOSS_BASE + streak * LOSS_INCREMENT, LOSS_MAX)
			add_money(peer_id, loss_reward)
			_loss_streak[peer_id] = streak + 1

func sync_to_peer(peer_id: int):
	if not multiplayer.is_server():
		return
	var money: int = _money.get(peer_id, START_MONEY)
	_sync_money.rpc_id(peer_id, money)

func remove_player(peer_id: int):
	_money.erase(peer_id)
	_loss_streak.erase(peer_id)

@rpc("authority", "reliable")
func _sync_money(amount: int) -> void:
	var local_id := multiplayer.get_unique_id()
	_money[local_id] = amount

# --- Public buy API (handles host-direct-call vs client-RPC) ---

func request_buy_weapon(weapon_id: int):
	var peer_id := multiplayer.get_unique_id()
	if multiplayer.is_server():
		_do_buy_weapon(peer_id, weapon_id)
	else:
		_rpc_buy_weapon.rpc_id(get_multiplayer_authority(), weapon_id)

func request_buy_kevlar():
	var peer_id := multiplayer.get_unique_id()
	if multiplayer.is_server():
		_do_buy_kevlar(peer_id)
	else:
		_rpc_buy_kevlar.rpc_id(get_multiplayer_authority())

func request_buy_grenade(grenade_type: int):
	var peer_id := multiplayer.get_unique_id()
	if multiplayer.is_server():
		_do_buy_grenade(peer_id, grenade_type)
	else:
		_rpc_buy_grenade.rpc_id(get_multiplayer_authority(), grenade_type)

func request_buy_defuse_kit():
	var peer_id := multiplayer.get_unique_id()
	if multiplayer.is_server():
		_do_buy_defuse_kit(peer_id)
	else:
		_rpc_buy_defuse_kit.rpc_id(get_multiplayer_authority())

# --- Internal: resolve peer_id to avatar and execute ---

func _get_avatar(peer_id: int) -> CharacterBody3D:
	var spawner := get_tree().current_scene.get_node_or_null("Network/Player Spawner")
	if spawner == null:
		return null
	return spawner.avatars.get(peer_id) as CharacterBody3D

func _do_buy_weapon(peer_id: int, weapon_id: int):
	var avatar := _get_avatar(peer_id)
	if avatar:
		try_buy_weapon(peer_id, weapon_id, avatar)

func _do_buy_kevlar(peer_id: int):
	var avatar := _get_avatar(peer_id)
	if avatar:
		try_buy_kevlar(peer_id, avatar)

func _do_buy_grenade(peer_id: int, grenade_type: int):
	var avatar := _get_avatar(peer_id)
	if avatar:
		try_buy_grenade(peer_id, grenade_type, avatar)

func _do_buy_defuse_kit(peer_id: int):
	var avatar := _get_avatar(peer_id)
	if avatar:
		try_buy_defuse_kit(peer_id, avatar)

# --- RPCs: client → server ---

@rpc("any_peer", "reliable")
func _rpc_buy_weapon(weapon_id: int) -> void:
	if not multiplayer.is_server():
		return
	_do_buy_weapon(multiplayer.get_remote_sender_id(), weapon_id)

@rpc("any_peer", "reliable")
func _rpc_buy_kevlar() -> void:
	if not multiplayer.is_server():
		return
	_do_buy_kevlar(multiplayer.get_remote_sender_id())

@rpc("any_peer", "reliable")
func _rpc_buy_grenade(grenade_type: int) -> void:
	if not multiplayer.is_server():
		return
	_do_buy_grenade(multiplayer.get_remote_sender_id(), grenade_type)

@rpc("any_peer", "reliable")
func _rpc_buy_defuse_kit() -> void:
	if not multiplayer.is_server():
		return
	_do_buy_defuse_kit(multiplayer.get_remote_sender_id())
