extends CharacterBody3D

@export var jump_strength = 5.0

@onready var display_name := $DisplayNameLabel3D as Label3D
@onready var input := $Input as PlayerInputFPS
@onready var tick_interpolator := $TickInterpolator as TickInterpolator
@onready var head := $Head as Node3D
@onready var hud := $HUD as CanvasGroup
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon_manager: WeaponManager = $Head/WeaponManager

static var _logger := NetfoxLogger.new("game", "Player")

var gravity = ProjectSettings.get_setting(&"physics/3d/default_gravity")
var health: int = 100
var death_tick: int = -1
var respawn_position: Vector3
var did_respawn := false
var respawn_tick: int = -1
var deaths := 0
var is_dead := false

# Kill attribution (rollback state)
var last_damage_attacker_id: int = -1
var last_damage_weapon_id: int = 0
var last_damage_tick: int = -1

# Armor and equipment
var armor: int = 0
var has_defuse_kit: bool = false

# Track deaths across tick loops to detect state changes
var _ackd_deaths := 0
var _was_hit := false
var _needs_teleport := false
var _has_played_round := false

# Frame-rate local camera
var _is_local := false
var _sim_transform: Transform3D
var _sim_head_transform: Transform3D
var _sim_yaw: float
var _sim_pitch: float
var _lerp_from_pos: Vector3
var _lerp_to_pos: Vector3

var team_manager: TeamManager
var round_manager: RoundManager

func _ready():
	display_name.text = name
	hud.hide()

	NetworkTime.before_tick_loop.connect(_before_tick_loop)
	NetworkTime.after_tick_loop.connect(_after_tick_loop)
	NetworkTime.on_tick.connect(_bomb_tick)

func setup_references(tm: TeamManager, rm: RoundManager):
	team_manager = tm
	round_manager = rm

func _setup_local_camera():
	_is_local = true
	tick_interpolator._disconnect_signals()
	tick_interpolator.enabled = false
	_sim_transform = global_transform
	_sim_head_transform = head.transform
	_sim_yaw = rotation.y
	_sim_pitch = head.rotation.x
	_lerp_from_pos = global_position
	_lerp_to_pos = global_position

func _before_tick_loop():
	_ackd_deaths = deaths
	_needs_teleport = false
	if _is_local:
		global_transform = _sim_transform
		head.transform = _sim_head_transform

func _after_tick_loop():
	if _is_local:
		_sim_transform = global_transform
		_sim_head_transform = head.transform
		_sim_yaw = rotation.y
		_sim_pitch = head.rotation.x
		_lerp_from_pos = _lerp_to_pos
		_lerp_to_pos = global_position

	if _needs_teleport:
		if _is_local:
			_lerp_from_pos = global_position
			_lerp_to_pos = global_position
		else:
			tick_interpolator.teleport()

	# Death detected during rollback loop
	if deaths > _ackd_deaths:
		if _is_local:
			_lerp_from_pos = global_position
			_lerp_to_pos = global_position
		else:
			tick_interpolator.teleport()
		is_dead = true
		$DieSFX.play()
		_hide_player()
		# Server: report kill with attribution, drop bomb
		if is_multiplayer_authority():
			_logger.warning("%s died at tick %s", [name, death_tick])
			# Drop bomb if carrier
			var bomb_node := get_tree().current_scene.get_node_or_null("Network/Bomb") as Bomb
			if bomb_node and bomb_node.carrier_id == get_player_id():
				bomb_node.drop_at(global_position)
			if round_manager:
				round_manager.report_kill(get_player_id(), last_damage_attacker_id, last_damage_weapon_id, death_tick)
			_sync_death.rpc(death_tick)
		_ackd_deaths = deaths

	if _was_hit:
		$HitSFX.play()
		_was_hit = false

func _process(_delta: float):
	if not _is_local:
		if input.is_multiplayer_authority():
			_setup_local_camera()
		else:
			return

	# Smooth position interpolation between ticks
	var f := NetworkTime.tick_factor
	global_position = _lerp_from_pos.lerp(_lerp_to_pos, f)

	# Frame-rate mouse look (recoil only affects raycast, not camera)
	rotation.y = _sim_yaw + (-input.mouse_rotation.y)
	head.rotation.x = clamp(_sim_pitch + (-input.mouse_rotation.x), -1.57, 1.57)
	head.rotation.y = 0
	head.rotation.z = 0

func _rollback_tick(delta: float, tick: int, is_fresh: bool) -> void:
	# Handle round respawn teleport inside rollback
	if respawn_tick >= 0 and tick == respawn_tick:
		global_position = respawn_position
		velocity = Vector3.ZERO
		did_respawn = true
		_needs_teleport = true
	else:
		did_respawn = false

	# Dead check
	if death_tick >= 0 and tick >= death_tick:
		return

	# Death detection inside rollback
	if health <= 0:
		death_tick = tick
		deaths += 1
		return

	# Freeze detection
	var is_frozen := round_manager != null and round_manager.freeze_end_tick >= 0 and tick < round_manager.freeze_end_tick

	# Handle look (always allowed)
	rotate_object_local(Vector3(0, 1, 0), input.look_angle.x)
	head.rotate_object_local(Vector3(1, 0, 0), input.look_angle.y)
	head.rotation.x = clamp(head.rotation.x, -1.57, 1.57)
	head.rotation.z = 0
	head.rotation.y = 0

	# Gravity + Jump
	_force_update_is_on_floor()
	if is_on_floor():
		if input.jump:
			velocity.y = jump_strength
	else:
		velocity.y -= gravity * delta

	# Movement speed from active weapon
	var speed := weapon_manager.get_move_speed() if weapon_manager else 5.0

	if is_frozen:
		velocity.x = 0.0
		velocity.z = 0.0
		velocity *= NetworkTime.physics_factor
		move_and_slide()
		velocity /= NetworkTime.physics_factor
		return

	# Apply movement
	var input_dir = input.movement
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.z)).normalized()
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	velocity *= NetworkTime.physics_factor
	move_and_slide()
	velocity /= NetworkTime.physics_factor

func _force_update_is_on_floor():
	var old_velocity = velocity
	velocity = Vector3.ZERO
	move_and_slide()
	velocity = old_velocity

func damage(amount: int, weapon_id: int = 0, attacker_id: int = -1, is_new_hit: bool = true):
	# Friendly fire check
	if team_manager and attacker_id >= 0 and attacker_id != get_player_id():
		if team_manager.get_team(attacker_id) == team_manager.get_team(get_player_id()):
			return

	# Armor absorption (Phase 3 — armor starts at 0)
	var armor_pen := 1.0
	var weapon := WeaponRegistry.get_weapon(weapon_id)
	if weapon:
		armor_pen = weapon.armor_penetration

	var effective := amount
	if armor > 0 and armor_pen < 1.0:
		var max_absorb := int(amount * (1.0 - armor_pen))
		var actual_absorb := mini(max_absorb, armor)
		effective = amount - actual_absorb
		armor -= actual_absorb

	health -= effective

	# Kill attribution
	if attacker_id >= 0:
		last_damage_attacker_id = attacker_id
		last_damage_weapon_id = weapon_id
		last_damage_tick = NetworkRollback.tick

	if is_new_hit:
		_was_hit = true
		_logger.warning("%s HP now at %s", [name, health])

func can_act(tick: int = -1) -> bool:
	if death_tick >= 0:
		return false
	var t := tick if tick >= 0 else NetworkRollback.tick
	if round_manager:
		if round_manager.freeze_end_tick >= 0 and t < round_manager.freeze_end_tick:
			return false
		if round_manager.round_end_tick >= 0 and t >= round_manager.round_end_tick:
			return false
	return true

func set_spectator():
	is_dead = true
	death_tick = NetworkTime.tick
	_hide_player()
	_sync_spectator.rpc(death_tick)

func round_respawn(spawn_pos: Vector3, survived: bool = false):
	is_dead = false
	health = 100
	deaths = 0
	death_tick = -1
	last_damage_attacker_id = -1
	last_damage_weapon_id = 0
	last_damage_tick = -1
	respawn_position = spawn_pos
	respawn_tick = NetworkTime.tick
	global_position = spawn_pos
	velocity = Vector3.ZERO
	did_respawn = true
	_has_played_round = true
	_show_player()

	if not survived:
		armor = 0
		has_defuse_kit = false
		var team := team_manager.get_team(get_player_id()) if team_manager else TeamManager.Team.T
		weapon_manager.set_default_loadout(team)
	else:
		# Keep weapons + armor, just cancel reload
		weapon_manager.reload_start_tick = -1
		weapon_manager.recoil_accumulator = 0.0

	_sync_round_respawn.rpc(spawn_pos, respawn_tick)

func _hide_player():
	$MeshInstance3D.hide()
	$Head/Nose.hide()
	$Head/BigGun.hide()
	weapon_manager.hide_weapons()
	$CollisionShape3D.disabled = true
	$DisplayNameLabel3D.hide()
	$Projection3D.hide()

func _show_player():
	$MeshInstance3D.show()
	$Head/Nose.show()
	$Head/BigGun.show()
	weapon_manager.show_weapons()
	$CollisionShape3D.disabled = false
	$DisplayNameLabel3D.show()
	$Projection3D.show()

func _bomb_tick(_delta: float, _tick: int):
	if not multiplayer.is_server():
		return
	if not is_multiplayer_authority():
		return
	if is_dead:
		return

	var bomb_node := get_tree().current_scene.get_node_or_null("Network/Bomb") as Bomb
	if bomb_node == null:
		return

	var pid := get_player_id()
	var team := team_manager.get_team(pid) if team_manager else TeamManager.Team.NONE

	# T player: start plant or pickup (cancel/validation handled by bomb._server_tick)
	if team == TeamManager.Team.T:
		if bomb_node.state == Bomb.BombState.CARRIED and bomb_node.carrier_id == pid:
			if input.use_held:
				var bombsites := get_tree().get_nodes_in_group("bombsite")
				for site in bombsites:
					if site is Bombsite and site.is_player_inside(self):
						bomb_node.try_start_plant(pid, site.site_name)
						break
		elif bomb_node.state == Bomb.BombState.DROPPED:
			if global_position.distance_to(bomb_node.position) < 2.0:
				bomb_node.try_pickup(pid)

	# CT player: start defuse (cancel/validation handled by bomb._server_tick)
	elif team == TeamManager.Team.CT:
		if bomb_node.state == Bomb.BombState.PLANTED:
			if input.use_held and global_position.distance_to(bomb_node.position) < 2.0:
				bomb_node.try_start_defuse(pid)

func get_player_id() -> int:
	return input.get_multiplayer_authority()

# --- RPCs ---
@rpc("authority", "call_local", "reliable")
func _sync_death(server_death_tick: int) -> void:
	is_dead = true
	death_tick = server_death_tick
	_hide_player()
	if _is_local:
		_lerp_from_pos = global_position
		_lerp_to_pos = global_position

@rpc("authority", "call_local", "reliable")
func _sync_spectator(server_death_tick: int) -> void:
	is_dead = true
	death_tick = server_death_tick
	_hide_player()
	if _is_local:
		_lerp_from_pos = global_position
		_lerp_to_pos = global_position

@rpc("authority", "call_local", "reliable")
func _sync_round_respawn(spawn_pos: Vector3, _respawn_tick: int) -> void:
	is_dead = false
	health = 100
	deaths = 0
	death_tick = -1
	last_damage_attacker_id = -1
	last_damage_weapon_id = 0
	last_damage_tick = -1
	respawn_position = spawn_pos
	respawn_tick = _respawn_tick
	global_position = spawn_pos
	velocity = Vector3.ZERO
	did_respawn = true
	_ackd_deaths = 0
	_show_player()
	if _is_local:
		_sim_transform = global_transform
		_sim_head_transform = head.transform
		_sim_yaw = rotation.y
		_sim_pitch = head.rotation.x
		_lerp_from_pos = spawn_pos
		_lerp_to_pos = spawn_pos
