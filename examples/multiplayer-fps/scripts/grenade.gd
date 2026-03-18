extends Node3D
class_name Grenade

enum GrenadeType { FLASH, SMOKE }

@export var grenade_type: GrenadeType = GrenadeType.FLASH
@export var fuse_time: float = 1.5
@export var throw_force: float = 20.0
@export var gravity: float = 15.0
@export var bounce_factor: float = 0.4

var velocity: Vector3 = Vector3.ZERO
var _fuse_timer: float = 0.0
var _detonated := false
var _owner_id: int = -1

func setup(origin: Vector3, direction: Vector3, owner_id: int, type: GrenadeType):
	global_position = origin
	grenade_type = type
	_owner_id = owner_id
	velocity = direction * throw_force + Vector3.UP * 5.0

	if type == GrenadeType.FLASH:
		fuse_time = 1.5
	else:
		fuse_time = 2.0

func _physics_process(delta: float):
	if _detonated:
		return

	# Simple physics
	velocity.y -= gravity * delta
	var new_pos := global_position + velocity * delta

	# Basic bounce off floor
	if new_pos.y < 0.1:
		new_pos.y = 0.1
		velocity.y = -velocity.y * bounce_factor
		velocity.x *= bounce_factor
		velocity.z *= bounce_factor

	global_position = new_pos

	# Fuse countdown
	_fuse_timer += delta
	if _fuse_timer >= fuse_time:
		_detonate()

func _detonate():
	if _detonated:
		return
	_detonated = true

	if not multiplayer.is_server():
		return

	match grenade_type:
		GrenadeType.FLASH:
			_flash_effect()
		GrenadeType.SMOKE:
			_smoke_effect()

func _flash_effect():
	var space := get_world_3d().direct_space_state
	var flash_pos := global_position

	# Check all players for flash
	var spawner := get_tree().current_scene.get_node_or_null("Network/Player Spawner")
	if spawner == null:
		queue_free()
		return

	for peer_id in spawner.avatars:
		var avatar = spawner.avatars[peer_id] as CharacterBody3D
		if avatar == null or avatar.is_dead:
			continue

		var head_pos: Vector3 = avatar.global_position + Vector3.UP * 0.7
		var distance := flash_pos.distance_to(head_pos)
		if distance > 30.0:
			continue

		# LOS check
		var query := PhysicsRayQueryParameters3D.create(flash_pos, head_pos)
		query.exclude = [avatar.get_rid()]
		var result := space.intersect_ray(query)

		if result.is_empty():
			# Direct line of sight — calculate flash duration
			var duration := _calculate_flash_duration(distance, avatar, head_pos, flash_pos)
			if duration > 0.0:
				_apply_flash.rpc_id(peer_id, duration)

	# Cleanup
	call_deferred("queue_free")

func _calculate_flash_duration(distance: float, avatar: CharacterBody3D, head_pos: Vector3, flash_pos: Vector3) -> float:
	# Base duration: closer = longer flash
	var base := lerpf(3.5, 0.5, clampf(distance / 25.0, 0.0, 1.0))

	# Facing check: looking at flash = full duration, away = reduced
	var head := avatar.get_node_or_null("Head") as Node3D
	if head:
		var to_flash := (flash_pos - head_pos).normalized()
		var facing := -head.global_transform.basis.z
		var dot := facing.dot(to_flash)
		if dot < 0.0:
			base *= 0.3  # Looking away
		else:
			base *= lerpf(0.5, 1.0, dot)

	return base

func _smoke_effect():
	# Spawn smoke zone at detonation position
	_spawn_smoke.rpc(global_position)
	# Smoke grenade stays alive for smoke duration, then frees itself
	set_physics_process(false)
	var smoke_duration := 18.0
	get_tree().create_timer(smoke_duration).timeout.connect(queue_free)

@rpc("authority", "call_local", "reliable")
func _apply_flash(duration: float) -> void:
	# Client-side: white screen effect
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	var rect := ColorRect.new()
	rect.color = Color(1, 1, 1, 1)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(rect)
	get_tree().current_scene.add_child(canvas)

	# Fade out
	var tween := get_tree().create_tween()
	tween.tween_property(rect, "color:a", 0.0, duration)
	tween.tween_callback(canvas.queue_free)

@rpc("authority", "call_local", "reliable")
func _spawn_smoke(pos: Vector3) -> void:
	# Client-side: visual smoke particles
	var smoke_node := Node3D.new()
	smoke_node.name = "SmokeCloud"
	smoke_node.global_position = pos
	get_tree().current_scene.add_child(smoke_node)

	# Simple visual: grey sphere mesh as placeholder
	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 3.0
	sphere.height = 4.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.6, 0.6, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	sphere.material = mat
	mesh_inst.mesh = sphere
	smoke_node.add_child(mesh_inst)

	get_tree().create_timer(18.0).timeout.connect(smoke_node.queue_free)
