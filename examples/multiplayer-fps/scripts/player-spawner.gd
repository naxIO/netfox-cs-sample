extends Node

@export var player_scene: PackedScene

var t_spawn_points: Array[Marker3D] = []
var ct_spawn_points: Array[Marker3D] = []
var team_manager: TeamManager
var round_manager: RoundManager
var avatars: Dictionary = {}

func _ready():
	team_manager = $"../TeamManager"
	round_manager = $"../RoundManager"

	# Discover spawn points from scene containers
	var scene_root := get_tree().current_scene
	var t_container := scene_root.get_node_or_null("T Spawns")
	if t_container:
		for child in t_container.get_children():
			if child is Marker3D:
				t_spawn_points.append(child)
	var ct_container := scene_root.get_node_or_null("CT Spawns")
	if ct_container:
		for child in ct_container.get_children():
			if child is Marker3D:
				ct_spawn_points.append(child)

	NetworkEvents.on_client_start.connect(_handle_connected)
	NetworkEvents.on_server_start.connect(_handle_host)
	NetworkEvents.on_peer_join.connect(_handle_new_peer)
	NetworkEvents.on_peer_leave.connect(_handle_leave)
	NetworkEvents.on_client_stop.connect(_handle_stop)
	NetworkEvents.on_server_stop.connect(_handle_stop)

	if round_manager:
		round_manager.round_started.connect(_handle_round_start)

func _handle_connected(id: int):
	_spawn(id)

func _handle_host():
	_spawn(1)
	# Auto-start match
	if round_manager:
		round_manager.start_match()

func _handle_new_peer(id: int):
	_spawn(id)
	if multiplayer.is_server():
		team_manager.sync_to_peer(id)
		if avatars.size() <= 2:
			# First opponent joined — restart round so both spawn alive
			round_manager.start_round()
		else:
			# 3+ players: sync state, spectate until next round
			round_manager.sync_to_peer(id)
			var avatar = avatars.get(id)
			if avatar and avatar.has_method("set_spectator"):
				avatar.call_deferred("set_spectator")

func _handle_leave(id: int):
	if not avatars.has(id):
		return

	var avatar = avatars[id] as Node
	avatar.queue_free()
	avatars.erase(id)

func _handle_stop():
	for avatar in avatars.values():
		avatar.queue_free()
	avatars.clear()

func _handle_round_start(_round_number: int):
	if not multiplayer.is_server():
		return
	# Respawn all players at their team spawn points
	for peer_id in avatars:
		var avatar = avatars[peer_id] as CharacterBody3D
		if avatar == null:
			continue
		var spawn_pos := get_team_spawn_point(peer_id)
		avatar.round_respawn(spawn_pos)

func _spawn(id: int):
	# Auto-assign team on server
	if multiplayer.is_server():
		team_manager.auto_assign(id)

	var avatar = player_scene.instantiate() as Node
	avatars[id] = avatar
	avatar.name += " #%d" % id
	add_child(avatar)
	avatar.global_position = get_team_spawn_point(id)

	# Avatar is always owned by server
	avatar.set_multiplayer_authority(1)

	# Pass references
	if avatar.has_method("setup_references"):
		avatar.setup_references(team_manager, round_manager)

	print("Spawned avatar %s at %s" % [avatar.name, multiplayer.get_unique_id()])

	# Avatar's input object is owned by player
	var input = avatar.find_child("Input")
	if input != null:
		input.set_multiplayer_authority(id)
		print("Set input(%s) ownership to %s" % [input.name, id])

	# Notify RollbackSynchronizer about ownership changes (required by netfox docs)
	var rollback_sync = avatar.find_child("RollbackSynchronizer")
	if rollback_sync and rollback_sync.has_method("process_settings"):
		rollback_sync.process_settings()

func get_team_spawn_point(peer_id: int, spawn_idx: int = 0) -> Vector3:
	var team := team_manager.get_team(peer_id)
	var points: Array[Marker3D]

	match team:
		TeamManager.Team.T:
			points = t_spawn_points
		TeamManager.Team.CT:
			points = ct_spawn_points
		_:
			# Fallback: use T spawns
			points = t_spawn_points

	if points.is_empty():
		return Vector3.ZERO

	var idx := hash(peer_id * 37 + spawn_idx * 19) % points.size()
	return points[idx].global_position

func get_next_spawn_point(peer_id: int, spawn_idx: int = 0) -> Vector3:
	return get_team_spawn_point(peer_id, spawn_idx)
