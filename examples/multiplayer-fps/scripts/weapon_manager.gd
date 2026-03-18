extends Node3D
class_name WeaponManager

@onready var input: PlayerInputFPS = $"../../Input"
@onready var player: CharacterBody3D = $"../.."
@onready var sound: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var bullethole: BulletHole = $BulletHole
@onready var fire_action := $"Fire Action" as RewindableAction
@onready var rollback_synchronizer := %RollbackSynchronizer as RollbackSynchronizer

# Rollback state
var inventory: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var active_slot: int = 0
var ammo: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var reserve: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var reload_start_tick: int = -1
var last_fire_by_slot: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1])
var recoil_accumulator: float = 0.0

# Grenade inventory (Phase 5)
var grenade_counts: PackedInt32Array = PackedInt32Array([0, 0])  # [flash, smoke]
var active_grenade_type: int = 0  # 0=Flash, 1=Smoke (only when slot 3 active)

var _pending_hit_result: Dictionary = {}
var _pending_grenades: Array[Dictionary] = []  # Buffered throws, consumed in _after_loop

# Weapon models (loaded at runtime)
var _knife_model: Node3D
var _gun_model: MeshInstance3D
var _grenade_model: Node3D
var _current_visible_slot: int = -1
var _knife_sound: AudioStreamPlayer3D

func _ready():
	fire_action.mutate(self)
	fire_action.mutate($"../../")
	NetworkTime.before_tick_loop.connect(_before_loop)
	NetworkTime.after_tick_loop.connect(_after_loop)
	_gun_model = $TinyGun
	_load_weapon_models()

func _load_weapon_models():
	# Knife model
	var knife_scene := load("res://examples/multiplayer-fps/models/knife.fbx") as PackedScene
	if knife_scene:
		_knife_model = knife_scene.instantiate()
		_knife_model.scale = Vector3(0.003, 0.003, 0.003)
		_knife_model.position = Vector3(0.15, -0.22, -0.35)
		_knife_model.rotation_degrees = Vector3(-90, 180, 0)
		add_child(_knife_model)
		_knife_model.hide()

	# Grenade model
	var grenade_scene := load("res://examples/multiplayer-fps/models/grenade.glb") as PackedScene
	if grenade_scene:
		_grenade_model = grenade_scene.instantiate()
		_grenade_model.scale = Vector3(0.08, 0.08, 0.08)
		_grenade_model.position = Vector3(0.1, -0.18, -0.25)
		add_child(_grenade_model)
		_grenade_model.hide()

	# Knife sound
	var slash_stream := load("res://examples/multiplayer-fps/sounds/knife/knife_slash1.wav")
	if slash_stream:
		_knife_sound = AudioStreamPlayer3D.new()
		_knife_sound.stream = slash_stream
		_knife_sound.max_distance = 10.0
		add_child(_knife_sound)

func _process(_delta: float):
	# Update weapon model visibility
	if active_slot != _current_visible_slot:
		_current_visible_slot = active_slot
		if _knife_model:
			_knife_model.visible = (active_slot == 0)
		if _gun_model:
			_gun_model.visible = (active_slot == 1 or active_slot == 2)
		if _grenade_model:
			_grenade_model.visible = (active_slot == 3)

func hide_weapons():
	if _knife_model:
		_knife_model.hide()
	if _gun_model:
		_gun_model.hide()
	if _grenade_model:
		_grenade_model.hide()
	_current_visible_slot = -1

func show_weapons():
	_current_visible_slot = -1  # Force refresh on next _process

func get_active_weapon() -> WeaponData:
	var wid := inventory[active_slot]
	if wid == 0:
		return null
	return WeaponRegistry.get_weapon(wid)

func get_move_speed() -> float:
	var weapon := get_active_weapon()
	if weapon:
		return weapon.move_speed
	return 5.0

func set_default_loadout(team: int):
	inventory = PackedInt32Array([WeaponRegistry.KNIFE, WeaponRegistry.get_default_pistol(team), 0, 0])
	active_slot = 0
	reload_start_tick = -1
	recoil_accumulator = 0.0
	last_fire_by_slot = PackedInt32Array([-1, -1, -1, -1])
	grenade_counts = PackedInt32Array([0, 0])
	active_grenade_type = 0
	for i in 4:
		var weapon := WeaponRegistry.get_weapon(inventory[i])
		if weapon:
			ammo[i] = weapon.magazine_size
			reserve[i] = weapon.reserve_size
		else:
			ammo[i] = 0
			reserve[i] = 0
	NetworkRollback.mutate(self)

func strip_weapons():
	inventory = PackedInt32Array([0, 0, 0, 0])
	active_slot = 0
	ammo = PackedInt32Array([0, 0, 0, 0])
	reserve = PackedInt32Array([0, 0, 0, 0])
	reload_start_tick = -1
	last_fire_by_slot = PackedInt32Array([-1, -1, -1, -1])
	recoil_accumulator = 0.0
	grenade_counts = PackedInt32Array([0, 0])
	active_grenade_type = 0
	NetworkRollback.mutate(self)

func give_weapon(weapon_id: int):
	var weapon := WeaponRegistry.get_weapon(weapon_id)
	if weapon == null:
		return
	inventory[weapon.slot] = weapon_id
	ammo[weapon.slot] = weapon.magazine_size
	reserve[weapon.slot] = weapon.reserve_size
	last_fire_by_slot[weapon.slot] = -1
	active_slot = weapon.slot
	NetworkRollback.mutate(self)

func _rollback_tick(delta: float, tick: int, _is_fresh: bool):
	if rollback_synchronizer.is_predicting():
		return

	# Skip if player dead
	if player.death_tick >= 0 and tick >= player.death_tick:
		return

	# Recoil recovery (always, even during freeze)
	var weapon := get_active_weapon()
	if weapon and recoil_accumulator > 0.0:
		recoil_accumulator = move_toward(recoil_accumulator, 0.0, weapon.recoil_recovery * delta)

	# Can't act checks (pass tick for correct rollback evaluation)
	if not player.can_act(tick):
		return

	# Handle weapon switching
	_handle_weapon_switch()

	# Handle reload
	_handle_reload(tick)

	# Handle firing
	_handle_fire(tick)

func _handle_weapon_switch():
	var new_slot := -1

	if input.slot_1 and inventory[0] != 0:
		new_slot = 0
	elif input.slot_2 and inventory[1] != 0:
		new_slot = 1
	elif input.slot_3 and inventory[2] != 0:
		new_slot = 2
	elif input.slot_4 and _has_grenades():
		new_slot = 3
	elif input.next_weapon:
		new_slot = _find_next_occupied_slot(1)
	elif input.prev_weapon:
		new_slot = _find_next_occupied_slot(-1)

	if new_slot >= 0 and new_slot != active_slot:
		active_slot = new_slot
		reload_start_tick = -1  # cancel reload on switch
		recoil_accumulator = 0.0
	elif new_slot == 3 and active_slot == 3:
		# Re-pressing slot 4 while on grenade slot: cycle grenade type
		_cycle_grenade_type()

func _has_grenades() -> bool:
	return grenade_counts[0] > 0 or grenade_counts[1] > 0

func _is_slot_occupied(slot: int) -> bool:
	if slot == 3:
		return _has_grenades()
	return inventory[slot] != 0

func _find_next_occupied_slot(direction: int) -> int:
	for i in range(1, 5):
		var slot := (active_slot + direction * i) % 4
		if slot < 0:
			slot += 4
		if _is_slot_occupied(slot):
			return slot
	return active_slot

func add_grenade(type: int) -> bool:
	## type: 0=flash, 1=smoke. Returns true if added.
	var max_count := 2 if type == 0 else 1
	if grenade_counts[type] >= max_count:
		return false
	grenade_counts[type] += 1
	NetworkRollback.mutate(self)
	return true

func _handle_reload(tick: int):
	var weapon := get_active_weapon()
	if weapon == null or weapon.fire_mode == WeaponData.FireMode.MELEE:
		reload_start_tick = -1
		return

	# Start reload if requested
	if input.reload_pressed and reload_start_tick < 0:
		if ammo[active_slot] < weapon.magazine_size and reserve[active_slot] > 0:
			reload_start_tick = tick

	# Complete reload
	if reload_start_tick >= 0:
		if NetworkTime.seconds_between(reload_start_tick, tick) >= weapon.reload_time:
			var needed := weapon.magazine_size - ammo[active_slot]
			var available := mini(needed, reserve[active_slot])
			ammo[active_slot] += available
			reserve[active_slot] -= available
			reload_start_tick = -1

func _handle_fire(tick: int):
	# Grenade throw (slot 3) — server-authoritative, no rollback
	if active_slot == 3 and _has_grenades():
		if input.fire_pressed:
			_throw_grenade()
		fire_action.set_active(false)
		return

	var weapon := get_active_weapon()
	if weapon == null:
		fire_action.set_active(false)
		return

	# Determine if we should fire
	var want_fire := false
	if weapon.fire_mode == WeaponData.FireMode.AUTO:
		want_fire = input.fire_held
	else:  # SEMI or MELEE
		want_fire = input.fire_pressed

	var can_fire := want_fire and _can_fire_weapon(weapon, tick)

	fire_action.set_active(can_fire)
	match fire_action.get_status():
		RewindableAction.CONFIRMING, RewindableAction.ACTIVE:
			_fire(weapon, tick)
		RewindableAction.CANCELLING:
			_unfire()

func _can_fire_weapon(weapon: WeaponData, tick: int) -> bool:
	# Check cooldown (per-slot)
	if last_fire_by_slot[active_slot] >= 0:
		if NetworkTime.seconds_between(last_fire_by_slot[active_slot], tick) < weapon.fire_rate:
			return false
	# Check ammo (melee has no ammo)
	if weapon.fire_mode != WeaponData.FireMode.MELEE:
		if ammo[active_slot] <= 0:
			return false
	# Check reload
	if reload_start_tick >= 0:
		return false
	return true

func _fire(weapon: WeaponData, tick: int):
	last_fire_by_slot[active_slot] = tick

	# Consume ammo
	if weapon.fire_mode != WeaponData.FireMode.MELEE:
		ammo[active_slot] -= 1

	# Recoil
	recoil_accumulator += weapon.recoil_per_shot

	# Raycast
	var hit := _raycast(weapon)
	if hit.is_empty():
		return

	_on_hit(hit, weapon)

func _unfire():
	fire_action.erase_context()

func _raycast(weapon: WeaponData) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var origin := global_transform.origin
	var direction := -global_transform.basis.z

	# Apply recoil to direction
	if recoil_accumulator > 0.0:
		var recoil_rad := deg_to_rad(recoil_accumulator)
		direction = direction.rotated(global_transform.basis.x, recoil_rad)

	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + direction * weapon.max_distance
	)

	return space.intersect_ray(query)

func _on_hit(result: Dictionary, weapon: WeaponData):
	var is_new_hit := false
	if not fire_action.has_context():
		fire_action.set_context(true)
		is_new_hit = true

	if is_new_hit:
		_pending_hit_result = result

	if result.collider.has_method("damage"):
		var attacker_id: int = player.get_player_id()
		result.collider.damage(weapon.damage, weapon.weapon_id, attacker_id, is_new_hit)
		NetworkRollback.mutate(result.collider)

func _cycle_grenade_type():
	# Cycle through available grenade types
	for i in range(1, 3):
		var next := (active_grenade_type + i) % 2
		if grenade_counts[next] > 0:
			active_grenade_type = next
			return

func _throw_grenade():
	if not _has_grenades():
		return
	# Ensure we have the selected type, otherwise cycle
	if grenade_counts[active_grenade_type] <= 0:
		_cycle_grenade_type()
		if grenade_counts[active_grenade_type] <= 0:
			return

	grenade_counts[active_grenade_type] -= 1

	# Buffer the throw — actual RPC fires in _after_loop (rollback-safe)
	_pending_grenades.append({
		"origin": global_transform.origin,
		"direction": -global_transform.basis.z,
		"owner_id": player.get_player_id(),
		"type": active_grenade_type
	})

	# Auto-switch if no grenades left
	if not _has_grenades():
		active_slot = 0

func _before_loop():
	_pending_grenades.clear()

func _after_loop():
	# Grenade spawns (deferred from rollback — fires once per throw)
	for pg in _pending_grenades:
		_spawn_grenade.rpc(pg["origin"], pg["direction"], pg["owner_id"], pg["type"])
	_pending_grenades.clear()

	if fire_action.has_confirmed():
		# Play weapon-appropriate sound
		if active_slot == 0 and _knife_sound:
			_knife_sound.play()
		else:
			sound.play()
		if not _pending_hit_result.is_empty():
			# No bullet holes for knife
			if active_slot != 0:
				bullethole.action(_pending_hit_result)
			_pending_hit_result = {}

@rpc("authority", "call_local", "reliable")
func _spawn_grenade(origin: Vector3, direction: Vector3, owner_id: int, type_idx: int) -> void:
	var grenade := Grenade.new()
	grenade.name = "Grenade_%d_%d" % [owner_id, NetworkTime.tick]
	get_tree().current_scene.add_child(grenade)
	var gtype: Grenade.GrenadeType = Grenade.GrenadeType.FLASH if type_idx == 0 else Grenade.GrenadeType.SMOKE
	grenade.setup(origin, direction, owner_id, gtype)
