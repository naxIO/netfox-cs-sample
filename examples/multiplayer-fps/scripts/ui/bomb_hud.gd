extends Control
class_name BombHUD

var bomb: Bomb
var _progress_bar: ProgressBar
var _timer_label: Label
var _status_label: Label

const COLOR_T := Color("#FFCC00")
const COLOR_CT := Color("#99CCFF")
const COLOR_DANGER := Color("#FF4444")

func _ready():
	var scene_root := get_tree().current_scene
	bomb = scene_root.get_node_or_null("Network/Bomb")
	mouse_filter = MOUSE_FILTER_IGNORE
	_build_ui()

func _build_ui():
	# Progress bar for plant/defuse
	_progress_bar = ProgressBar.new()
	_progress_bar.name = "BombProgress"
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 1.0
	_progress_bar.step = 0.01
	_progress_bar.show_percentage = false
	_progress_bar.mouse_filter = MOUSE_FILTER_IGNORE

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.1, 0.1, 0.1, 0.7)
	_progress_bar.add_theme_stylebox_override("background", bg_style)

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = COLOR_T
	_progress_bar.add_theme_stylebox_override("fill", fill_style)

	add_child(_progress_bar)
	_progress_bar.hide()

	# Bomb timer label
	_timer_label = Label.new()
	_timer_label.name = "BombTimer"
	_timer_label.add_theme_font_size_override("font_size", 24)
	_timer_label.add_theme_color_override("font_color", COLOR_DANGER)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_timer_label)
	_timer_label.hide()

	# Status label (BOMB PLANTED, DEFUSING, etc.)
	_status_label = Label.new()
	_status_label.name = "BombStatus"
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", COLOR_DANGER)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_status_label)
	_status_label.hide()

func _process(_delta: float):
	if bomb == null:
		return

	var vp := get_viewport_rect().size

	match bomb.state:
		Bomb.BombState.PLANTING:
			_progress_bar.value = bomb.get_plant_progress()
			_progress_bar.size = Vector2(200, 12)
			_progress_bar.position = Vector2(vp.x / 2.0 - 100, vp.y * 0.65)
			_progress_bar.show()
			_status_label.text = "PLANTING..."
			_status_label.add_theme_color_override("font_color", COLOR_T)
			_status_label.size = Vector2(200, 24)
			_status_label.position = Vector2(vp.x / 2.0 - 100, vp.y * 0.65 - 28)
			_status_label.show()
			_timer_label.hide()

		Bomb.BombState.PLANTED:
			_progress_bar.hide()
			var remaining := bomb.get_bomb_time_remaining()
			_timer_label.text = "%.1f" % remaining
			_timer_label.add_theme_color_override("font_color", COLOR_DANGER if remaining < 10.0 else COLOR_T)
			_timer_label.size = Vector2(100, 32)
			_timer_label.position = Vector2(vp.x / 2.0 - 50, vp.y * 0.35)
			_timer_label.show()
			_status_label.text = "BOMB PLANTED"
			_status_label.add_theme_color_override("font_color", COLOR_DANGER)
			_status_label.size = Vector2(200, 24)
			_status_label.position = Vector2(vp.x / 2.0 - 100, vp.y * 0.35 - 28)
			_status_label.show()

		Bomb.BombState.DEFUSING:
			_progress_bar.value = bomb.get_defuse_progress()
			_progress_bar.size = Vector2(200, 12)
			_progress_bar.position = Vector2(vp.x / 2.0 - 100, vp.y * 0.65)
			_progress_bar.show()
			var remaining := bomb.get_bomb_time_remaining()
			_timer_label.text = "%.1f" % remaining
			_timer_label.add_theme_color_override("font_color", COLOR_DANGER if remaining < 10.0 else COLOR_T)
			_timer_label.size = Vector2(100, 32)
			_timer_label.position = Vector2(vp.x / 2.0 - 50, vp.y * 0.35)
			_timer_label.show()
			_status_label.text = "DEFUSING..."
			_status_label.add_theme_color_override("font_color", COLOR_CT)
			_status_label.size = Vector2(200, 24)
			_status_label.position = Vector2(vp.x / 2.0 - 100, vp.y * 0.65 - 28)
			_status_label.show()

		_:
			_progress_bar.hide()
			_timer_label.hide()
			_status_label.hide()
