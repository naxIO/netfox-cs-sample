extends Node
class_name RoundManager

enum RoundState { WARMUP, FREEZE_TIME, ACTIVE, ROUND_END }

signal round_state_changed(new_state: RoundState)
signal round_started(round_number: int)
signal round_ended(winner: TeamManager.Team)

@export var freeze_time: float = 5.0
@export var round_time: float = 115.0
@export var round_end_time: float = 5.0
@export var max_rounds: int = 24
@export var rounds_to_win: int = 13

var state: RoundState = RoundState.WARMUP
var timer: float = 0.0
var round_number: int = 0
var score: Dictionary = { TeamManager.Team.T: 0, TeamManager.Team.CT: 0 }
var freeze_end_tick: int = -1
var active_end_tick: int = -1
var round_end_tick: int = -1

# Tracking alive players per round (synced to clients via RPC)
var _alive_players: Dictionary = {} # peer_id -> bool
var _last_winner: TeamManager.Team = TeamManager.Team.NONE

var team_manager: TeamManager

func _ready():
	team_manager = $"../TeamManager"
	set_process(false)
	NetworkEvents.on_peer_leave.connect(_handle_peer_leave)

func start_match():
	if not multiplayer.is_server():
		return
	round_number = 0
	score = { TeamManager.Team.T: 0, TeamManager.Team.CT: 0 }
	_sync_score.rpc(score[TeamManager.Team.T], score[TeamManager.Team.CT])
	start_round()

func start_round():
	if not multiplayer.is_server():
		return

	round_number += 1
	freeze_end_tick = NetworkTime.tick + int(freeze_time * float(NetworkTime.tickrate))
	active_end_tick = freeze_end_tick + int(round_time * float(NetworkTime.tickrate))
	round_end_tick = -1
	_mark_all_alive()
	_change_state(RoundState.FREEZE_TIME, freeze_time)
	_sync_round_start.rpc(round_number, freeze_end_tick, active_end_tick)

func _process(delta: float):
	# Local timer countdown for HUD display only
	if timer > 0:
		timer -= delta

	# Only server handles state transitions
	if not multiplayer.is_server():
		return

	var current_tick := NetworkTime.tick

	# Tick-based transitions for gameplay-critical boundaries
	if state == RoundState.FREEZE_TIME and current_tick >= freeze_end_tick:
		_change_state(RoundState.ACTIVE, round_time)
	elif state == RoundState.ACTIVE and current_tick >= active_end_tick:
		# Time ran out — CTs win
		end_round(TeamManager.Team.CT)
	elif state == RoundState.ROUND_END and timer <= 0:
		# ROUND_END display duration is cosmetic, frame-based is fine
		if _check_match_over():
			return
		start_round()

func report_kill(victim_id: int, _killer_id: int):
	if not multiplayer.is_server():
		return
	# Tick-based: round must be active (past freeze, before timer expiry, not ended)
	if round_end_tick >= 0:
		return
	if NetworkTime.tick < freeze_end_tick:
		return
	if NetworkTime.tick >= active_end_tick:
		return

	_alive_players[victim_id] = false
	_sync_player_alive.rpc(victim_id, false)

	# Check if a whole team is eliminated
	var t_alive := _count_alive(TeamManager.Team.T)
	var ct_alive := _count_alive(TeamManager.Team.CT)

	if t_alive == 0 and ct_alive == 0:
		end_round(TeamManager.Team.CT)
	elif t_alive == 0:
		end_round(TeamManager.Team.CT)
	elif ct_alive == 0:
		end_round(TeamManager.Team.T)

func end_round(winner: TeamManager.Team):
	if not multiplayer.is_server():
		return
	if round_end_tick >= 0:
		return

	round_end_tick = NetworkTime.tick
	_last_winner = winner
	score[winner] += 1
	_sync_score.rpc(score[TeamManager.Team.T], score[TeamManager.Team.CT])
	_sync_round_end.rpc(winner)
	_change_state(RoundState.ROUND_END, round_end_time)
	round_ended.emit(winner)

func is_player_alive(peer_id: int) -> bool:
	return _alive_players.get(peer_id, false)

func sync_to_peer(peer_id: int):
	## Send full state to a late-joining peer.
	_sync_state.rpc_id(peer_id, state, timer)
	_sync_score.rpc_id(peer_id, score[TeamManager.Team.T], score[TeamManager.Team.CT])
	_sync_round_start.rpc_id(peer_id, round_number, freeze_end_tick, active_end_tick)
	for pid in _alive_players:
		_sync_player_alive.rpc_id(peer_id, pid, _alive_players[pid])
	if state == RoundState.ROUND_END and _last_winner != TeamManager.Team.NONE:
		_sync_round_end.rpc_id(peer_id, _last_winner)

func _count_alive(team: TeamManager.Team) -> int:
	var count := 0
	for peer_id in team_manager.get_team_members(team):
		if _alive_players.get(peer_id, false):
			count += 1
	return count

func _mark_all_alive():
	_alive_players.clear()
	for peer_id in team_manager.assignments:
		if team_manager.get_team(peer_id) != TeamManager.Team.NONE:
			_alive_players[peer_id] = true
	# Broadcast alive states to all clients
	for pid in _alive_players:
		_sync_player_alive.rpc(pid, _alive_players[pid])

func _change_state(new_state: RoundState, duration: float):
	state = new_state
	timer = duration
	set_process(true)
	_sync_state.rpc(new_state, duration)
	round_state_changed.emit(new_state)

func _handle_peer_leave(peer_id: int) -> void:
	_alive_players.erase(peer_id)

func _check_match_over() -> bool:
	if score[TeamManager.Team.T] >= rounds_to_win or score[TeamManager.Team.CT] >= rounds_to_win:
		# TODO: Match end handling
		return true
	if round_number >= max_rounds:
		return true
	return false

# --- RPCs: Server -> All Clients ---

@rpc("authority", "call_local", "reliable")
func _sync_state(new_state: int, duration: float) -> void:
	state = new_state as RoundState
	timer = duration
	set_process(true)
	round_state_changed.emit(state)

@rpc("authority", "call_local", "reliable")
func _sync_score(t_score: int, ct_score: int) -> void:
	score[TeamManager.Team.T] = t_score
	score[TeamManager.Team.CT] = ct_score

@rpc("authority", "call_local", "reliable")
func _sync_round_start(round_num: int, _freeze_end: int, _active_end: int) -> void:
	round_number = round_num
	freeze_end_tick = _freeze_end
	active_end_tick = _active_end
	round_end_tick = -1
	round_started.emit(round_number)

@rpc("authority", "call_local", "reliable")
func _sync_round_end(winner: int) -> void:
	round_ended.emit(winner as TeamManager.Team)

@rpc("authority", "call_local", "reliable")
func _sync_player_alive(peer_id: int, alive: bool) -> void:
	_alive_players[peer_id] = alive
