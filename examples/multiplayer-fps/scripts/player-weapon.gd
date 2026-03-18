extends Node3D
class_name PlayerFPSWeapon

@export var fire_cooldown: float = 0.25
@export var damage_amount: int = 34
@export var max_distance: float = 1000.0

@onready var input: PlayerInputFPS = $"../../Input"
@onready var player: CharacterBody3D = $"../.."
@onready var sound: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var bullethole: BulletHole = $BulletHole
@onready var fire_action := $"Fire Action" as RewindableAction
@onready var rollback_synchronizer := %RollbackSynchronizer as RollbackSynchronizer

var last_fire: int = -1
var _pending_hit_result: Dictionary = {}

func _ready():
	fire_action.mutate(self)       # Mutate self so last_fire can be rolled back
	fire_action.mutate($"../../")  # Mutate player so health can be rolled back
	NetworkTime.after_tick_loop.connect(_after_loop)

func _rollback_tick(_dt: float, tick: int, _is_fresh: bool):
	if rollback_synchronizer.is_predicting():
		return

	var can_fire := input.fire and _can_fire()

	# Tick-based gating: death, freeze, round end
	if player.death_tick >= 0 and tick >= player.death_tick:
		can_fire = false
	if player.round_manager:
		if player.round_manager.freeze_end_tick >= 0 and tick < player.round_manager.freeze_end_tick:
			can_fire = false
		if player.round_manager.round_end_tick >= 0 and tick >= player.round_manager.round_end_tick:
			can_fire = false

	fire_action.set_active(can_fire)
	match fire_action.get_status():
		RewindableAction.CONFIRMING, RewindableAction.ACTIVE:
			_fire()
		RewindableAction.CANCELLING:
			_unfire()

func _after_loop():
	if fire_action.has_confirmed():
		sound.play()
		if not _pending_hit_result.is_empty():
			bullethole.action(_pending_hit_result)
			_pending_hit_result = {}

func _can_fire() -> bool:
	return NetworkTime.seconds_between(last_fire, NetworkRollback.tick) >= fire_cooldown

func _fire():
	last_fire = NetworkRollback.tick

	var hit := _raycast()
	if hit.is_empty():
		return

	_on_hit(hit)

func _unfire():
	fire_action.erase_context()

func _raycast() -> Dictionary:
	var space := get_world_3d().direct_space_state
	var origin := global_transform.origin
	var direction := -global_transform.basis.z

	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + direction * max_distance
	)

	return space.intersect_ray(query)

func _on_hit(result: Dictionary):
	var is_new_hit := false
	if not fire_action.has_context():
		fire_action.set_context(true)
		is_new_hit = true

	if is_new_hit:
		_pending_hit_result = result

	if result.collider.has_method("damage"):
		result.collider.damage(damage_amount, is_new_hit)
		NetworkRollback.mutate(result.collider)
