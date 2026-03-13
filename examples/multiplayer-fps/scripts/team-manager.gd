extends Node
class_name TeamManager

enum Team { NONE = -1, T = 0, CT = 1 }

signal team_changed(peer_id: int, team: Team)

# peer_id -> Team
var assignments: Dictionary = {}

func _ready():
	NetworkEvents.on_peer_leave.connect(_handle_peer_leave)

func get_team(peer_id: int) -> Team:
	return assignments.get(peer_id, Team.NONE) as Team

func get_team_members(team: Team) -> Array[int]:
	var members: Array[int] = []
	for peer_id in assignments:
		if assignments[peer_id] == team:
			members.append(peer_id)
	return members

func get_team_name(team: Team) -> String:
	match team:
		Team.T: return "Terrorists"
		Team.CT: return "Counter-Terrorists"
		_: return "Unassigned"

func auto_assign(peer_id: int) -> Team:
	var t_count := get_team_members(Team.T).size()
	var ct_count := get_team_members(Team.CT).size()
	var team := Team.T if t_count <= ct_count else Team.CT
	assign_team(peer_id, team)
	return team

func assign_team(peer_id: int, team: Team) -> void:
	if not multiplayer.is_server():
		return

	assignments[peer_id] = team
	_sync_assignment.rpc(peer_id, team)
	team_changed.emit(peer_id, team)

@rpc("authority", "call_local", "reliable")
func _sync_assignment(peer_id: int, team: int) -> void:
	assignments[peer_id] = team as Team
	team_changed.emit(peer_id, team as Team)

func sync_to_peer(peer_id: int) -> void:
	## Send all current team assignments to a late-joining peer.
	for pid in assignments:
		_sync_assignment.rpc_id(peer_id, pid, assignments[pid])

func _handle_peer_leave(peer_id: int) -> void:
	assignments.erase(peer_id)
