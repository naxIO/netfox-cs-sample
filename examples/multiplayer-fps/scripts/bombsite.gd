extends Area3D
class_name Bombsite

@export var site_name: String = "A"

func _ready():
	monitoring = true
	monitorable = true
	add_to_group("bombsite")

	# Create default collision shape if none assigned
	var has_shape := false
	for child in get_children():
		if child is CollisionShape3D and child.shape != null:
			has_shape = true
			break
	if not has_shape:
		var shape := BoxShape3D.new()
		shape.size = Vector3(8, 4, 8)
		var col := CollisionShape3D.new()
		col.shape = shape
		add_child(col)

func is_player_inside(player: CharacterBody3D) -> bool:
	var overlapping := get_overlapping_bodies()
	return player in overlapping
