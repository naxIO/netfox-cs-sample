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

var team_manager: TeamManager
var round_manager: RoundManager

func _ready():
	display_name.text = name
	hud.hide()

	NetworkTime.on_tick.connect(_tick)
	NetworkTime.after_tick_loop.connect(_after_tick_loop)

func setup_references(tm: TeamManager, rm: RoundManager):
	team_manager = tm
	round_manager = rm

func _tick(dt: float, tick: int):
	# Use death_tick (replicated) instead of is_dead (not rollback-safe)
	if death_tick >= 0:
		return

	if health <= 0:
		$DieSFX.play()
		deaths += 1
		_die()

func _after_tick_loop():
	if did_respawn:
		tick_interpolator.teleport()

func _rollback_tick(delta: float, tick: int, is_fresh: bool) -> void:
	# Handle round respawn teleport inside rollback for proper integration
	if respawn_tick >= 0 and tick == respawn_tick:
		global_position = respawn_position
		velocity = Vector3.ZERO
		did_respawn = true
	else:
		did_respawn = false

	# Use death_tick (replicated via MultiplayerSynchronizer) for rollback-safe
	# dead check. During resimulation, tick < death_tick = alive, tick >= death_tick = dead.
	if death_tick >= 0 and tick >= death_tick:
		return

	# Use freeze_end_tick for rollback-safe freeze detection.
	# freeze_end_tick is fixed once set, so tick < freeze_end_tick is deterministic during resimulation.
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

func damage():
	$HitSFX.play()
	if is_multiplayer_authority():
		health -= 34
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
	_sync_death.rpc()

func _die():
	if not is_multiplayer_authority():
		return

	_logger.warning("%s died", [name])
	is_dead = true
	death_tick = NetworkTime.tick

	# Report kill to round manager (tick-based, not frame-state-based)
	if round_manager:
		round_manager.report_kill(get_player_id(), -1)

	_sync_death.rpc()

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

@rpc("authority", "call_local", "reliable")
func _sync_death() -> void:
	is_dead = true
	_hide_player()

@rpc("authority", "call_local", "reliable")
func _sync_round_respawn(spawn_pos: Vector3, _respawn_tick: int) -> void:
	is_dead = false
	health = 100
	death_tick = -1
	respawn_position = spawn_pos
	respawn_tick = _respawn_tick
	global_position = spawn_pos
	velocity = Vector3.ZERO
	did_respawn = true
	_show_player()
