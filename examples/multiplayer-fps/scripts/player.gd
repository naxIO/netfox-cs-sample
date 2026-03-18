extends CharacterBody3D

@export var speed = 5.0
@export var jump_strength = 5.0

@onready var display_name := $DisplayNameLabel3D as Label3D
@onready var input := $Input as PlayerInputFPS
@onready var tick_interpolator := $TickInterpolator as TickInterpolator
@onready var head := $Head as Node3D
@onready var hud := $HUD as CanvasGroup
@onready var camera: Camera3D = $Head/Camera3D

static var _logger := NetfoxLogger.new("game", "Player")

var gravity = ProjectSettings.get_setting(&"physics/3d/default_gravity")
var health: int = 100
var death_tick: int = -1
var respawn_position: Vector3
var did_respawn := false
var respawn_tick: int = -1
var deaths := 0
var is_dead := false

# Track deaths across tick loops to detect state changes (rollback-fps pattern)
var _ackd_deaths := 0
var _was_hit := false
var _needs_teleport := false

var team_manager: TeamManager
var round_manager: RoundManager

func _ready():
	display_name.text = name
	hud.hide()

	NetworkTime.before_tick_loop.connect(_before_tick_loop)
	NetworkTime.after_tick_loop.connect(_after_tick_loop)

func setup_references(tm: TeamManager, rm: RoundManager):
	team_manager = tm
	round_manager = rm

func _before_tick_loop():
	_ackd_deaths = deaths
	_needs_teleport = false

func _after_tick_loop():
	# Teleport if any respawn happened during this tick loop (catch-up safe)
	if _needs_teleport:
		tick_interpolator.teleport()

	# Death detected during rollback loop
	if deaths > _ackd_deaths:
		tick_interpolator.teleport()
		is_dead = true
		$DieSFX.play()
		_hide_player()
		# Server: report kill and send immediate visual RPC to clients
		if is_multiplayer_authority():
			_logger.warning("%s died at tick %s", [name, death_tick])
			if round_manager:
				round_manager.report_kill(get_player_id(), -1, death_tick)
			_sync_death.rpc(death_tick)
		_ackd_deaths = deaths

	if _was_hit:
		$HitSFX.play()
		_was_hit = false

func _rollback_tick(delta: float, tick: int, is_fresh: bool) -> void:
	# Handle round respawn teleport inside rollback for proper integration
	if respawn_tick >= 0 and tick == respawn_tick:
		global_position = respawn_position
		velocity = Vector3.ZERO
		did_respawn = true
		_needs_teleport = true  # Accumulates across loop, survives catch-up
	else:
		did_respawn = false

	# Dead check: skip processing for dead player (deterministic, rollback-safe)
	if death_tick >= 0 and tick >= death_tick:
		return

	# Death detection inside rollback — same tick as damage, no one-frame delay
	if health <= 0:
		death_tick = tick
		deaths += 1
		return

	# Freeze detection (tick-based, deterministic during resimulation)
	var is_frozen := round_manager != null and round_manager.freeze_end_tick >= 0 and tick < round_manager.freeze_end_tick

	# Handle look (always allowed, even during freeze)
	rotate_object_local(Vector3(0, 1, 0), input.look_angle.x)
	head.rotate_object_local(Vector3(1, 0, 0), input.look_angle.y)
	head.rotation.x = clamp(head.rotation.x, -1.57, 1.57)
	head.rotation.z = 0
	head.rotation.y = 0

	# Gravity + Jump (always allowed, even during freeze)
	_force_update_is_on_floor()
	if is_on_floor():
		if input.jump:
			velocity.y = jump_strength
	else:
		velocity.y -= gravity * delta

	if is_frozen:
		# Freeze: no horizontal movement, but keep vertical (jump/gravity)
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

	# move_and_slide assumes physics delta
	# multiplying velocity by NetworkTime.physics_factor compensates for it
	velocity *= NetworkTime.physics_factor
	move_and_slide()
	velocity /= NetworkTime.physics_factor

func _force_update_is_on_floor():
	var old_velocity = velocity
	velocity = Vector3.ZERO
	move_and_slide()
	velocity = old_velocity

func damage(amount: int = 34, is_new_hit: bool = true):
	health -= amount
	if is_new_hit:
		_was_hit = true
		_logger.warning("%s HP now at %s", [name, health])

func can_act() -> bool:
	## Returns false if the player is dead, frozen, or round has ended.
	if death_tick >= 0:
		return false
	if round_manager:
		if round_manager.freeze_end_tick >= 0 and NetworkTime.tick < round_manager.freeze_end_tick:
			return false
		if round_manager.round_end_tick >= 0:
			return false
	return true

func set_spectator():
	## Called on server for mid-round joiners — dead until next round.
	is_dead = true
	death_tick = NetworkTime.tick
	_hide_player()
	_sync_spectator.rpc(death_tick)

func round_respawn(spawn_pos: Vector3):
	# Called by spawner at round start (server only)
	is_dead = false
	health = 100
	deaths = 0
	death_tick = -1
	respawn_position = spawn_pos
	respawn_tick = NetworkTime.tick
	global_position = spawn_pos
	velocity = Vector3.ZERO
	did_respawn = true
	_show_player()

	_sync_round_respawn.rpc(spawn_pos, respawn_tick)

func _hide_player():
	# Hide visuals but keep node alive for spectating
	$MeshInstance3D.hide()
	$Head/Nose.hide()
	$Head/BigGun.hide()
	$Head/PlayerFPSWeapon/TinyGun.hide()
	$CollisionShape3D.disabled = true
	$DisplayNameLabel3D.hide()
	$Projection3D.hide()

func _show_player():
	$MeshInstance3D.show()
	$Head/Nose.show()
	$Head/BigGun.show()
	$Head/PlayerFPSWeapon/TinyGun.show()
	$CollisionShape3D.disabled = false
	$DisplayNameLabel3D.show()
	$Projection3D.show()

func get_player_id() -> int:
	return input.get_multiplayer_authority()

# --- RPCs ---
# _sync_death is cosmetic: fast visual feedback for remote clients.
# Gameplay gating uses death_tick/deaths (rollback state via RollbackSynchronizer).
@rpc("authority", "call_local", "reliable")
func _sync_death(server_death_tick: int) -> void:
	is_dead = true
	death_tick = server_death_tick
	_hide_player()

@rpc("authority", "call_local", "reliable")
func _sync_spectator(server_death_tick: int) -> void:
	is_dead = true
	death_tick = server_death_tick
	_hide_player()

@rpc("authority", "call_local", "reliable")
func _sync_round_respawn(spawn_pos: Vector3, _respawn_tick: int) -> void:
	is_dead = false
	health = 100
	deaths = 0
	death_tick = -1
	respawn_position = spawn_pos
	respawn_tick = _respawn_tick
	global_position = spawn_pos
	velocity = Vector3.ZERO
	did_respawn = true
	_ackd_deaths = 0
	_show_player()
