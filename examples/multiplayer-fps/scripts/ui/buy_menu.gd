extends Control
class_name BuyMenu

var economy_manager: EconomyManager
var team_manager: TeamManager
var round_manager: RoundManager
var _panel: PanelContainer
var _vbox: VBoxContainer
var _is_open := false

func _ready():
	var scene_root := get_tree().current_scene
	economy_manager = scene_root.get_node_or_null("Network/EconomyManager")
	team_manager = scene_root.get_node_or_null("Network/TeamManager")
	round_manager = scene_root.get_node_or_null("Network/RoundManager")

	mouse_filter = MOUSE_FILTER_IGNORE
	_build_panel()
	hide()

func _build_panel():
	_panel = PanelContainer.new()
	_panel.name = "BuyPanel"

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.12, 0.92)
	style.border_color = Color(0.4, 0.4, 0.4, 0.6)
	style.set_border_width_all(1)
	style.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", style)

	_vbox = VBoxContainer.new()
	_vbox.name = "BuyVBox"
	_panel.add_child(_vbox)
	add_child(_panel)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("buy_menu"):
		if _is_open:
			_close()
		elif _can_buy():
			_open()

	if _is_open and event.is_action_pressed("escape"):
		_close()

	# Number keys for quick buy
	if _is_open and event is InputEventKey and event.pressed:
		_handle_buy_key(event)

func _process(_delta: float):
	if not _is_open:
		return

	# Close if no longer in freeze time
	if not _can_buy():
		_close()
		return

	# Position panel
	var vp := get_viewport_rect().size
	_panel.size = Vector2(340, 400)
	_panel.position = Vector2(vp.x / 2.0 - 170, vp.y / 2.0 - 200)

func _can_buy() -> bool:
	if round_manager == null:
		return false
	# Tick-based check only — deterministic, no state-transition race
	if round_manager.freeze_end_tick < 0:
		return false
	if NetworkTime.tick >= round_manager.freeze_end_tick:
		return false
	# Must be alive (spectators/dead can't buy)
	var local_id := multiplayer.get_unique_id()
	if not round_manager.is_player_alive(local_id):
		return false
	return true

func _open():
	_is_open = true
	_rebuild_menu()
	show()

func _close():
	_is_open = false
	hide()

func _rebuild_menu():
	for child in _vbox.get_children():
		child.queue_free()

	var local_id := multiplayer.get_unique_id()
	var money := economy_manager.get_money(local_id) if economy_manager else 0
	var team := team_manager.get_team(local_id) if team_manager else TeamManager.Team.T

	# Title
	var title := Label.new()
	title.text = "BUY MENU  -  $%d" % money
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("#FFDD44"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(title)

	var sep := HSeparator.new()
	_vbox.add_child(sep)

	# Pistols
	_add_section("PISTOLS")
	if team == TeamManager.Team.T:
		_add_weapon_row("1", WeaponRegistry.GLOCK, money)
	else:
		_add_weapon_row("1", WeaponRegistry.USP, money)

	# Rifles
	_add_section("RIFLES")
	if team == TeamManager.Team.T:
		_add_weapon_row("2", WeaponRegistry.AK47, money)
	else:
		_add_weapon_row("2", WeaponRegistry.M4A1, money)
	_add_weapon_row("3", WeaponRegistry.AWP, money)

	# Grenades
	_add_section("GRENADES")
	_add_equipment_row("4", "Flashbang", EconomyManager.FLASH_PRICE, money)
	_add_equipment_row("5", "Smoke", EconomyManager.SMOKE_PRICE, money)

	# Equipment
	_add_section("EQUIPMENT")
	_add_equipment_row("6", "Kevlar", EconomyManager.KEVLAR_PRICE, money)
	if team == TeamManager.Team.CT:
		_add_equipment_row("7", "Defuse Kit", EconomyManager.DEFUSE_KIT_PRICE, money)

func _add_section(text: String):
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 8
	_vbox.add_child(spacer)

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color("#AAAAAA"))
	_vbox.add_child(lbl)

func _add_weapon_row(key: String, weapon_id: int, money: int):
	var weapon := WeaponRegistry.get_weapon(weapon_id)
	if weapon == null:
		return

	var hbox := HBoxContainer.new()
	var can_afford := money >= weapon.price

	var key_lbl := Label.new()
	key_lbl.text = "[%s]" % key
	key_lbl.add_theme_font_size_override("font_size", 14)
	key_lbl.add_theme_color_override("font_color", Color.YELLOW if can_afford else Color.DARK_GRAY)
	key_lbl.custom_minimum_size.x = 40
	hbox.add_child(key_lbl)

	var name_lbl := Label.new()
	name_lbl.text = weapon.weapon_name
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color.WHITE if can_afford else Color.DARK_GRAY)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_lbl)

	var price_lbl := Label.new()
	price_lbl.text = "$%d" % weapon.price
	price_lbl.add_theme_font_size_override("font_size", 14)
	price_lbl.add_theme_color_override("font_color", Color("#00FF00") if can_afford else Color.DARK_RED)
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(price_lbl)

	_vbox.add_child(hbox)

func _add_equipment_row(key: String, item_name: String, price: int, money: int):
	var hbox := HBoxContainer.new()
	var can_afford := money >= price

	var key_lbl := Label.new()
	key_lbl.text = "[%s]" % key
	key_lbl.add_theme_font_size_override("font_size", 14)
	key_lbl.add_theme_color_override("font_color", Color.YELLOW if can_afford else Color.DARK_GRAY)
	key_lbl.custom_minimum_size.x = 40
	hbox.add_child(key_lbl)

	var name_lbl := Label.new()
	name_lbl.text = item_name
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color.WHITE if can_afford else Color.DARK_GRAY)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_lbl)

	var price_lbl := Label.new()
	price_lbl.text = "$%d" % price
	price_lbl.add_theme_font_size_override("font_size", 14)
	price_lbl.add_theme_color_override("font_color", Color("#00FF00") if can_afford else Color.DARK_RED)
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(price_lbl)

	_vbox.add_child(hbox)

func _handle_buy_key(event: InputEventKey):
	if economy_manager == null:
		return

	var local_id := multiplayer.get_unique_id()
	var team := team_manager.get_team(local_id) if team_manager else TeamManager.Team.T

	match event.physical_keycode:
		KEY_1:
			var pistol_id := WeaponRegistry.GLOCK if team == TeamManager.Team.T else WeaponRegistry.USP
			economy_manager.request_buy_weapon(pistol_id)
		KEY_2:
			var rifle_id := WeaponRegistry.AK47 if team == TeamManager.Team.T else WeaponRegistry.M4A1
			economy_manager.request_buy_weapon(rifle_id)
		KEY_3:
			economy_manager.request_buy_weapon(WeaponRegistry.AWP)
		KEY_4:
			economy_manager.request_buy_grenade(0)  # Flash
		KEY_5:
			economy_manager.request_buy_grenade(1)  # Smoke
		KEY_6:
			economy_manager.request_buy_kevlar()
		KEY_7:
			if team == TeamManager.Team.CT:
				economy_manager.request_buy_defuse_kit()

	# Rebuild to update money display
	call_deferred("_rebuild_menu")
