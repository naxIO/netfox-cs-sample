extends Control
class_name RoundHUD

var round_manager: RoundManager
var team_manager: TeamManager

@onready var timer_label := $TimerLabel as Label
@onready var score_label := $ScoreLabel as Label
@onready var state_label := $StateLabel as Label
@onready var scoreboard_panel := $ScoreboardPanel as PanelContainer

var scoreboard_vbox: VBoxContainer
var _scoreboard_rebuild_timer := 0.0

const COLOR_T := Color("#FFCC00")
const COLOR_CT := Color("#99CCFF")
const COLOR_DEAD := Color("#884444")
const COLOR_GREEN := Color("#00FF00")
const COLOR_HEADER := Color("#AAAAAA")

func _ready():
	var scene_root := get_tree().current_scene
	round_manager = scene_root.get_node_or_null("Network/RoundManager")
	team_manager = scene_root.get_node_or_null("Network/TeamManager")

	_setup_styles()
	scoreboard_panel.hide()
	state_label.hide()

	if round_manager:
		round_manager.round_state_changed.connect(_on_state_changed)
		round_manager.round_ended.connect(_on_round_ended)

func _setup_styles():
	mouse_filter = MOUSE_FILTER_IGNORE

	# Timer
	timer_label.add_theme_font_size_override("font_size", 20)
	timer_label.add_theme_color_override("font_color", COLOR_GREEN)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.mouse_filter = MOUSE_FILTER_IGNORE

	# Score
	score_label.add_theme_font_size_override("font_size", 16)
	score_label.add_theme_color_override("font_color", Color.WHITE)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.mouse_filter = MOUSE_FILTER_IGNORE

	# State
	state_label.add_theme_font_size_override("font_size", 36)
	state_label.add_theme_color_override("font_color", Color.YELLOW)
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	state_label.mouse_filter = MOUSE_FILTER_IGNORE

	# Scoreboard panel — CS 1.6 dark background
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.05, 0.1, 0.88)
	panel_style.border_color = Color(0.4, 0.4, 0.4, 0.6)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(0)
	panel_style.set_content_margin_all(12)
	scoreboard_panel.add_theme_stylebox_override("panel", panel_style)

	# Remove old Label, replace with VBoxContainer
	var old_label := scoreboard_panel.get_node_or_null("Label")
	if old_label:
		old_label.queue_free()

	scoreboard_vbox = VBoxContainer.new()
	scoreboard_vbox.name = "ScoreboardVBox"
	scoreboard_vbox.mouse_filter = MOUSE_FILTER_IGNORE
	scoreboard_panel.add_child(scoreboard_vbox)

func _process(_delta: float):
	if round_manager == null:
		return

	var vp := get_viewport_rect().size

	# Position elements
	timer_label.size = Vector2(100, 28)
	timer_label.position = Vector2(vp.x / 2.0 - 50, vp.y - 34)

	score_label.size = Vector2(200, 24)
	score_label.position = Vector2(vp.x / 2.0 - 100, 6)

	state_label.size = Vector2(500, 60)
	state_label.position = Vector2(vp.x / 2.0 - 250, vp.y / 2.0 - 30)

	scoreboard_panel.size = Vector2(560, 420)
	scoreboard_panel.position = Vector2(vp.x / 2.0 - 280, vp.y / 2.0 - 210)

	# Timer content
	var time_left: float = maxf(0.0, round_manager.timer)
	var minutes := int(time_left) / 60
	var seconds := int(time_left) % 60
	timer_label.text = "%d:%02d" % [minutes, seconds]

	if round_manager.state == RoundManager.RoundState.ACTIVE and time_left <= 10.0:
		timer_label.add_theme_color_override("font_color", Color.RED)
	else:
		timer_label.add_theme_color_override("font_color", COLOR_GREEN)

	# Score content
	var t_score := int(round_manager.score.get(TeamManager.Team.T, 0))
	var ct_score := int(round_manager.score.get(TeamManager.Team.CT, 0))
	score_label.text = "T  %d  :  %d  CT" % [t_score, ct_score]

	# Scoreboard (Tab) — throttle rebuilds to max 2/sec to avoid UI churn
	if Input.is_action_pressed("scoreboard"):
		_scoreboard_rebuild_timer -= _delta
		if _scoreboard_rebuild_timer <= 0:
			_rebuild_scoreboard()
			_scoreboard_rebuild_timer = 0.5
		scoreboard_panel.show()
	else:
		scoreboard_panel.hide()
		_scoreboard_rebuild_timer = 0.0

func _on_state_changed(new_state: RoundManager.RoundState):
	match new_state:
		RoundManager.RoundState.FREEZE_TIME:
			state_label.text = "FREEZE TIME"
			state_label.add_theme_color_override("font_color", Color.YELLOW)
			state_label.show()
		RoundManager.RoundState.ACTIVE:
			state_label.hide()
		RoundManager.RoundState.ROUND_END:
			pass

func _on_round_ended(winner: TeamManager.Team):
	var winner_name := "ROUND OVER"
	var color := Color.YELLOW
	if team_manager:
		winner_name = team_manager.get_team_name(winner).to_upper() + " WIN"
		color = COLOR_T if winner == TeamManager.Team.T else COLOR_CT
	state_label.text = winner_name
	state_label.add_theme_color_override("font_color", color)
	state_label.show()

# --- Scoreboard building with Control nodes ---

func _rebuild_scoreboard():
	if team_manager == null or scoreboard_vbox == null:
		return

	# Clear previous content
	for child in scoreboard_vbox.get_children():
		child.queue_free()

	var t_members := team_manager.get_team_members(TeamManager.Team.T)
	var ct_members := team_manager.get_team_members(TeamManager.Team.CT)
	var t_score := int(round_manager.score.get(TeamManager.Team.T, 0))
	var ct_score := int(round_manager.score.get(TeamManager.Team.CT, 0))

	# Title
	_add_label_centered("Counter-Strike", Color.WHITE, 20)
	_add_label_centered("Round %d" % round_manager.round_number, Color.GRAY, 12)
	_add_spacer(8)

	# Column headers
	_add_row(["Name", "Score", "Deaths", "Latency"], COLOR_HEADER, 13)
	_add_separator()

	# T header
	_add_team_header("Terrorists", t_members.size(), t_score, COLOR_T)

	# T players
	for peer_id in t_members:
		var alive := round_manager.is_player_alive(peer_id)
		var c := COLOR_T if alive else COLOR_DEAD
		var status := "ALIVE" if alive else "DEAD"
		_add_row(["  Player #%d" % peer_id, "0", "0", status], c, 13)

	_add_spacer(4)
	_add_separator()

	# CT header
	_add_team_header("Counter-Terrorists", ct_members.size(), ct_score, COLOR_CT)

	# CT players
	for peer_id in ct_members:
		var alive := round_manager.is_player_alive(peer_id)
		var c := COLOR_CT if alive else COLOR_DEAD
		var status := "ALIVE" if alive else "DEAD"
		_add_row(["  Player #%d" % peer_id, "0", "0", status], c, 13)

func _add_label_centered(text: String, color: Color, font_size: int):
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.mouse_filter = MOUSE_FILTER_IGNORE
	scoreboard_vbox.add_child(lbl)

func _add_team_header(team_name: String, player_count: int, team_score: int, color: Color):
	var hbox := HBoxContainer.new()
	hbox.mouse_filter = MOUSE_FILTER_IGNORE

	var name_lbl := Label.new()
	name_lbl.text = "%s  -  %d players" % [team_name, player_count]
	name_lbl.add_theme_color_override("font_color", color)
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.mouse_filter = MOUSE_FILTER_IGNORE
	hbox.add_child(name_lbl)

	var score_lbl := Label.new()
	score_lbl.text = str(team_score)
	score_lbl.add_theme_color_override("font_color", Color.WHITE)
	score_lbl.add_theme_font_size_override("font_size", 14)
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_lbl.mouse_filter = MOUSE_FILTER_IGNORE
	hbox.add_child(score_lbl)

	scoreboard_vbox.add_child(hbox)

func _add_row(columns: Array, color: Color, font_size: int):
	var hbox := HBoxContainer.new()
	hbox.mouse_filter = MOUSE_FILTER_IGNORE

	# Column widths: Name=5, Score=2, Deaths=2, Latency=2
	var ratios := [5, 2, 2, 2]

	for i in columns.size():
		var lbl := Label.new()
		lbl.text = columns[i]
		lbl.add_theme_color_override("font_color", color)
		lbl.add_theme_font_size_override("font_size", font_size)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.size_flags_stretch_ratio = ratios[i] if i < ratios.size() else 1
		lbl.mouse_filter = MOUSE_FILTER_IGNORE
		if i > 0:
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hbox.add_child(lbl)

	scoreboard_vbox.add_child(hbox)

func _add_separator():
	var sep := HSeparator.new()
	sep.mouse_filter = MOUSE_FILTER_IGNORE
	sep.add_theme_color_override("separator", Color(0.4, 0.4, 0.4))
	scoreboard_vbox.add_child(sep)

func _add_spacer(height: int):
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	spacer.mouse_filter = MOUSE_FILTER_IGNORE
	scoreboard_vbox.add_child(spacer)
