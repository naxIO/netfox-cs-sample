extends Node
class_name Bomb

enum BombState { IDLE, CARRIED, PLANTING, DROPPED, PLANTED, DEFUSING, EXPLODED, DEFUSED }

signal bomb_planted(site_name: String)
signal bomb_exploded()
signal bomb_defused()
signal bomb_dropped(position: Vector3)
signal bomb_picked_up(carrier_id: int)

@export var plant_time: float = 3.0
@export var defuse_time: float = 10.0
@export var defuse_kit_time: float = 5.0
@export var bomb_timer: float = 40.0

var state: BombState = BombState.IDLE
var carrier_id: int = -1
var position: Vector3 = Vector3.ZERO
var planted_site: String = ""
var planted_tick: int = -1

# Progress tracking (tick-based)
var _plant_start_tick: int = -1
var _defuse_start_tick: int = -1
var _defuser_id: int = -1

var team_manager: TeamManager
var round_manager: RoundManager

func _ready():
	team_manager = get_tree().current_scene.get_node_or_null("Network/TeamManager")
	round_manager = get_tree().current_scene.get_node_or_null("Network/RoundManager")

	if multiplayer.is_server():
		NetworkTime.on_tick.connect(_server_tick)
		NetworkEvents.on_peer_leave.connect(_handle_peer_leave)

	if round_manager:
		round_manager.round_started.connect(_on_round_started)

func reset():
	state = BombState.IDLE
	carrier_id = -1
	position = Vector3.ZERO
	planted_site = ""
	planted_tick = -1
	_plant_start_tick = -1
	_defuse_start_tick = -1
	_defuser_id = -1

func assign_to_player(peer_id: int):
	if not multiplayer.is_server():
		return
	carrier_id = peer_id
	state = BombState.CARRIED
	_broadcast_state()
	bomb_picked_up.emit(carrier_id)

func drop_at(pos: Vector3):
	if not multiplayer.is_server():
		return
	if state != BombState.CARRIED and state != BombState.PLANTING:
		return
	state = BombState.DROPPED
	carrier_id = -1
	position = pos
	_plant_start_tick = -1
	_broadcast_state()
	bomb_dropped.emit(pos)

func try_start_plant(peer_id: int, bombsite_name: String) -> bool:
	if not multiplayer.is_server():
		return false
	if state != BombState.CARRIED:
		return false
	if carrier_id != peer_id:
		return false
	if team_manager.get_team(peer_id) != TeamManager.Team.T:
		return false
	if round_manager.state != RoundManager.RoundState.ACTIVE:
		return false

	state = BombState.PLANTING
	planted_site = bombsite_name
	_plant_start_tick = NetworkTime.tick
	_broadcast_state()
	return true

func cancel_plant():
	if not multiplayer.is_server():
		return
	if state != BombState.PLANTING:
		return
	state = BombState.CARRIED
	_plant_start_tick = -1
	_broadcast_state()

func try_start_defuse(peer_id: int) -> bool:
	if not multiplayer.is_server():
		return false
	if state != BombState.PLANTED:
		return false
	if team_manager.get_team(peer_id) != TeamManager.Team.CT:
		return false
	if round_manager.state != RoundManager.RoundState.ACTIVE:
		return false

	state = BombState.DEFUSING
	_defuser_id = peer_id
	_defuse_start_tick = NetworkTime.tick
	_broadcast_state()
	return true

func cancel_defuse():
	if not multiplayer.is_server():
		return
	if state != BombState.DEFUSING:
		return
	state = BombState.PLANTED
	_defuser_id = -1
	_defuse_start_tick = -1
	_broadcast_state()

func try_pickup(peer_id: int) -> bool:
	if not multiplayer.is_server():
		return false
	if state != BombState.DROPPED:
		return false
	if team_manager.get_team(peer_id) != TeamManager.Team.T:
		return false
	carrier_id = peer_id
	state = BombState.CARRIED
	_broadcast_state()
	bomb_picked_up.emit(carrier_id)
	return true

func get_plant_progress() -> float:
	if state != BombState.PLANTING or _plant_start_tick < 0:
		return 0.0
	return NetworkTime.seconds_between(_plant_start_tick, NetworkTime.tick) / plant_time

func get_defuse_progress() -> float:
	if state != BombState.DEFUSING or _defuse_start_tick < 0:
		return 0.0
	var time_needed := _get_defuse_time()
	return NetworkTime.seconds_between(_defuse_start_tick, NetworkTime.tick) / time_needed

func get_bomb_time_remaining() -> float:
	if state != BombState.PLANTED and state != BombState.DEFUSING:
		return bomb_timer
	if planted_tick < 0:
		return bomb_timer
	var elapsed := NetworkTime.seconds_between(planted_tick, NetworkTime.tick)
	return maxf(0.0, bomb_timer - elapsed)

func _get_defuse_time() -> float:
	var spawner := get_tree().current_scene.get_node_or_null("Network/Player Spawner")
	if spawner and _defuser_id >= 0:
		var avatar: CharacterBody3D = spawner.avatars.get(_defuser_id) as CharacterBody3D
		if avatar and avatar.has_defuse_kit:
			return defuse_kit_time
	return defuse_time

func _server_tick(_delta: float, tick: int):
	if not multiplayer.is_server():
		return

	var spawner := get_tree().current_scene.get_node_or_null("Network/Player Spawner")

	# --- Phase 1: Validate + Cancel (before any completion) ---

	# Validate ongoing plant
	if state == BombState.PLANTING and carrier_id >= 0:
		if spawner:
			var avatar: CharacterBody3D = spawner.avatars.get(carrier_id) as CharacterBody3D
			if avatar == null or avatar.is_dead:
				drop_at(position)
				return
			position = avatar.global_position
			# Check use_held from carrier's input
			var input_node = avatar.get_node_or_null("Input") as PlayerInputFPS
			if input_node and not input_node.use_held:
				cancel_plant()
				return
			# Check still on bombsite
			var on_site := false
			for site in get_tree().get_nodes_in_group("bombsite"):
				if site is Bombsite and site.is_player_inside(avatar):
					on_site = true
					break
			if not on_site:
				cancel_plant()
				return

	# Track carrier position (non-planting)
	if state == BombState.CARRIED and carrier_id >= 0:
		if spawner:
			var avatar: CharacterBody3D = spawner.avatars.get(carrier_id) as CharacterBody3D
			if avatar and not avatar.is_dead:
				position = avatar.global_position
			else:
				drop_at(position)
				return

	# Validate ongoing defuse
	if state == BombState.DEFUSING and _defuser_id >= 0:
		if spawner:
			var avatar: CharacterBody3D = spawner.avatars.get(_defuser_id) as CharacterBody3D
			if avatar == null or avatar.is_dead:
				cancel_defuse()
				return
			if avatar.global_position.distance_to(position) > 2.5:
				cancel_defuse()
				return
			# Check use_held from defuser's input
			var input_node = avatar.get_node_or_null("Input") as PlayerInputFPS
			if input_node and not input_node.use_held:
				cancel_defuse()
				return
		else:
			cancel_defuse()
			return

	# --- Phase 2: Completion (only if validation passed) ---

	match state:
		BombState.PLANTING:
			if _plant_start_tick >= 0 and NetworkTime.seconds_between(_plant_start_tick, tick) >= plant_time:
				_complete_plant(tick)
		BombState.PLANTED, BombState.DEFUSING:
			# Bomb timer (ticks during both planted and defusing)
			if planted_tick >= 0 and NetworkTime.seconds_between(planted_tick, tick) >= bomb_timer:
				_explode()

	# Defuse completion (after bomb timer, so explosion takes priority)
	if state == BombState.DEFUSING and _defuse_start_tick >= 0:
		if NetworkTime.seconds_between(_defuse_start_tick, tick) >= _get_defuse_time():
			_complete_defuse()

func _complete_plant(tick: int):
	state = BombState.PLANTED
	planted_tick = tick
	position = _get_carrier_position()
	carrier_id = -1
	_plant_start_tick = -1
	_broadcast_state()
	bomb_planted.emit(planted_site)

func _complete_defuse():
	state = BombState.DEFUSED
	_defuse_start_tick = -1
	_defuser_id = -1
	_broadcast_state()
	bomb_defused.emit()
	if round_manager:
		round_manager.end_round(TeamManager.Team.CT)

func _explode():
	state = BombState.EXPLODED
	_broadcast_state()
	bomb_exploded.emit()
	if round_manager:
		round_manager.end_round(TeamManager.Team.T)

func _get_carrier_position() -> Vector3:
	var spawner := get_tree().current_scene.get_node_or_null("Network/Player Spawner")
	if spawner and carrier_id >= 0:
		var avatar: CharacterBody3D = spawner.avatars.get(carrier_id) as CharacterBody3D
		if avatar:
			return avatar.global_position
	return position

func _on_round_started(_round_number: int):
	reset()

func _handle_peer_leave(peer_id: int):
	if not multiplayer.is_server():
		return
	if carrier_id == peer_id and (state == BombState.CARRIED or state == BombState.PLANTING):
		drop_at(position)
	if _defuser_id == peer_id and state == BombState.DEFUSING:
		cancel_defuse()

func sync_to_peer(peer_id: int):
	_sync_state.rpc_id(peer_id, state, carrier_id, position, planted_site, planted_tick, _plant_start_tick, _defuse_start_tick, _defuser_id)

func _broadcast_state():
	_sync_state.rpc(state, carrier_id, position, planted_site, planted_tick, _plant_start_tick, _defuse_start_tick, _defuser_id)

@rpc("authority", "call_local", "reliable")
func _sync_state(new_state: int, new_carrier: int, new_pos: Vector3, site: String, p_tick: int, plant_start: int, defuse_start: int, defuser: int) -> void:
	state = new_state as BombState
	carrier_id = new_carrier
	position = new_pos
	planted_site = site
	planted_tick = p_tick
	_plant_start_tick = plant_start
	_defuse_start_tick = defuse_start
	_defuser_id = defuser
