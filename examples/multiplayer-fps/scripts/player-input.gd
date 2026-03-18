extends BaseNetInput
class_name PlayerInputFPS

@export var mouse_sensitivity: float = 1.0
@export var big_gun: MeshInstance3D
@export var hud: CanvasGroup

@onready var camera: Camera3D = $"../Head/Camera3D"

# Config variables
var is_setup: bool = false
var override_mouse: bool = false

# Input latches (set in _input, consumed in _gather)
var _fire_pressed_latch := false
var _reload_pressed_latch := false
var _next_weapon_latch := false
var _prev_weapon_latch := false
var _slot_1_latch := false
var _slot_2_latch := false
var _slot_3_latch := false
var _slot_4_latch := false

# Input variables (frame-rate mouse accumulator)
var mouse_rotation: Vector2 = Vector2.ZERO

# Rollback input properties (set in _gather)
var look_angle: Vector2 = Vector2.ZERO
var movement: Vector3 = Vector3.ZERO
var jump: bool = false
var fire_held: bool = false
var fire_pressed: bool = false
var reload_pressed: bool = false
var next_weapon: bool = false
var prev_weapon: bool = false
var slot_1: bool = false
var slot_2: bool = false
var slot_3: bool = false
var slot_4: bool = false
var use_held: bool = false

func _notification(what):
	if what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		override_mouse = false

func _input(event: InputEvent) -> void:
	if !is_multiplayer_authority(): return

	if event is InputEventMouseMotion:
		mouse_rotation.y += event.relative.x * mouse_sensitivity
		mouse_rotation.x += event.relative.y * mouse_sensitivity

	if event.is_action_pressed("escape"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		override_mouse = true

	# Latched inputs — captured on press, consumed once in _gather
	if event.is_action_pressed("mouse_weapon_fire"):
		_fire_pressed_latch = true
	if event.is_action_pressed("weapon_reload"):
		_reload_pressed_latch = true
	if event.is_action_pressed("weapon_next"):
		_next_weapon_latch = true
	if event.is_action_pressed("weapon_prev"):
		_prev_weapon_latch = true
	if event.is_action_pressed("weapon_slot_1"):
		_slot_1_latch = true
	if event.is_action_pressed("weapon_slot_2"):
		_slot_2_latch = true
	if event.is_action_pressed("weapon_slot_3"):
		_slot_3_latch = true
	if event.is_action_pressed("weapon_slot_4"):
		_slot_4_latch = true

func _gather():
	if !is_setup:
		setup()

	# Movement (continuous)
	var mx = Input.get_axis("move_west", "move_east")
	var mz = Input.get_axis("move_north", "move_south")
	movement = Vector3(mx, 0, mz)

	jump = Input.is_action_pressed("move_jump")

	# Fire: held state + one-shot pressed latch
	fire_held = Input.is_action_pressed("mouse_weapon_fire")
	fire_pressed = _fire_pressed_latch
	_fire_pressed_latch = false

	# Weapon inputs (latched)
	reload_pressed = _reload_pressed_latch
	_reload_pressed_latch = false

	next_weapon = _next_weapon_latch
	_next_weapon_latch = false

	prev_weapon = _prev_weapon_latch
	_prev_weapon_latch = false

	slot_1 = _slot_1_latch
	_slot_1_latch = false

	slot_2 = _slot_2_latch
	_slot_2_latch = false

	slot_3 = _slot_3_latch
	_slot_3_latch = false

	slot_4 = _slot_4_latch
	_slot_4_latch = false

	use_held = Input.is_action_pressed("use_action")

	# Mouse look
	if override_mouse:
		look_angle = Vector2.ZERO
		mouse_rotation = Vector2.ZERO
	else:
		look_angle = Vector2(-mouse_rotation.y, -mouse_rotation.x)
		mouse_rotation = Vector2.ZERO

func setup():
	is_setup = true
	camera.current = true
	big_gun.hide()
	hud.show()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
