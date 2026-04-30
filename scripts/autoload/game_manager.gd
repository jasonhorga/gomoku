extends Node

const _GameLogic = preload("res://scripts/game_logic.gd")
const _PlayerController = preload("res://scripts/player/player_controller.gd")

enum GameMode { ONLINE, LOCAL_PVP, VS_AI, AI_VS_AI }

var logic = _GameLogic.new()
var mode: GameMode = GameMode.ONLINE
var players: Array = [null, null]  # [0]=BLACK controller, [1]=WHITE controller
var my_color: int = -1
var is_my_turn: bool = false
var ai_move_delay: float = 0.5
var forbidden_enabled: bool = false

signal stone_placed(row: int, col: int, color: int)
signal turn_changed(is_my_turn: bool)
signal game_ended(winner: int)
signal opponent_reset_requested()
signal game_reset()


func _ready() -> void:
	# P2b smoke test — trail of checkpoint logs so we can see exactly which
	# plugin call crashes on device. Without console on iOS the log file is
	# our only window; each Log.info is flushed, so whatever appears last
	# identifies the line that blew up.
	Log.info("GM", "_ready enter, OS=%s" % OS.get_name())
	_smoke_test_plugin()
	Log.info("GM", "_ready done")


func _smoke_test_plugin() -> void:
	Log.info("Plugin", "smoke test enter")
	var has_singleton := Engine.has_singleton("GomokuNeural")
	Log.info("Plugin", "has_singleton=%s" % has_singleton)
	if not has_singleton:
		Log.info("Plugin", "GomokuNeural not present (OK on %s)" % OS.get_name())
		return
	var plugin = Engine.get_singleton("GomokuNeural")
	Log.info("Plugin", "got singleton=%s" % plugin)
	var version: String = plugin.plugin_version()
	Log.info("Plugin", "version=%s" % version)

	# Handcrafted board: black at (7,7)(7,8), white blocker at (7,6).
	# Expect pattern-greedy black→(7,9) or (7,5); white→(7,9) block.
	var test_board: Array = []
	for _r in range(15):
		var row: Array = []
		for _c in range(15):
			row.append(0)
		test_board.append(row)
	test_board[7][7] = 1
	test_board[7][8] = 1
	test_board[7][6] = 2
	Log.info("Plugin", "built test_board, calling get_move (black)…")

	var t0_us: int = Time.get_ticks_usec()
	var black_move: Vector2i = plugin.get_move(5, test_board, 1, Vector2i(7, 8))
	var dt_black_us: int = Time.get_ticks_usec() - t0_us
	Log.info("Plugin", "black→(%d,%d) in %dus" % [black_move.x, black_move.y, dt_black_us])

	var t1_us: int = Time.get_ticks_usec()
	var white_move: Vector2i = plugin.get_move(5, test_board, 2, Vector2i(7, 8))
	var dt_white_us: int = Time.get_ticks_usec() - t1_us
	Log.info("Plugin", "white→(%d,%d) in %dus" % [white_move.x, white_move.y, dt_white_us])

	# L6 probe — triggers CoreML lazy-load so version() string tells us
	# whether the .mlmodelc landed in the bundle correctly.
	var t2_us: int = Time.get_ticks_usec()
	var l6_move: Vector2i = plugin.get_move(6, test_board, 1, Vector2i(7, 8))
	var dt_l6_us: int = Time.get_ticks_usec() - t2_us
	Log.info("Plugin", "L6→(%d,%d) in %dus (first call triggers CoreML load)" % [l6_move.x, l6_move.y, dt_l6_us])
	Log.info("Plugin", "post-L6 version=%s" % plugin.plugin_version())
	Log.info("Plugin", "smoke test done")


# ---- Setup methods (call before entering game scene) ----

func setup_online(player_color: int) -> void:
	mode = GameMode.ONLINE
	my_color = player_color
	forbidden_enabled = false
	logic.forbidden_enabled = false
	var human = load("res://scripts/player/human_player.gd").new()
	human.color = player_color
	var remote = load("res://scripts/player/network_player.gd").new()
	remote.color = _GameLogic.WHITE if player_color == _GameLogic.BLACK else _GameLogic.BLACK
	players[_color_index(player_color)] = human
	players[_color_index(remote.color)] = remote
	# Network reset handshake
	if not NetworkManager.reset_requested.is_connected(_on_reset_requested):
		NetworkManager.reset_requested.connect(_on_reset_requested)
	if not NetworkManager.reset_accepted.is_connected(_on_reset_accepted):
		NetworkManager.reset_accepted.connect(_on_reset_accepted)


func setup_local_pvp(p_forbidden_enabled: bool = false) -> void:
	mode = GameMode.LOCAL_PVP
	my_color = -1  # both are local
	forbidden_enabled = p_forbidden_enabled
	logic.forbidden_enabled = forbidden_enabled
	var p1 = load("res://scripts/player/human_player.gd").new()
	p1.color = _GameLogic.BLACK
	var p2 = load("res://scripts/player/human_player.gd").new()
	p2.color = _GameLogic.WHITE
	players[0] = p1
	players[1] = p2
	_disconnect_network_signals()


func setup_vs_ai(human_color: int, ai_engine, p_forbidden_enabled: bool = false) -> void:
	mode = GameMode.VS_AI
	my_color = human_color
	forbidden_enabled = p_forbidden_enabled
	logic.forbidden_enabled = forbidden_enabled
	Log.info("Engine", "setup_vs_ai engine=%s" % _describe_engine(ai_engine))
	var human = load("res://scripts/player/human_player.gd").new()
	human.color = human_color
	# ai_engine: an AIEngine instance, will be wrapped in LocalAIPlayer
	var LocalAIPlayer = load("res://scripts/player/local_ai_player.gd")
	var ai = LocalAIPlayer.new(ai_engine)
	ai.color = _GameLogic.WHITE if human_color == _GameLogic.BLACK else _GameLogic.BLACK
	players[_color_index(human_color)] = human
	players[_color_index(ai.color)] = ai
	_disconnect_network_signals()


func setup_ai_vs_ai(engine_black, engine_white, p_forbidden_enabled: bool = false) -> void:
	mode = GameMode.AI_VS_AI
	my_color = -1
	forbidden_enabled = p_forbidden_enabled
	logic.forbidden_enabled = forbidden_enabled
	Log.info("Engine", "setup_ai_vs_ai black=%s white=%s" % [
		_describe_engine(engine_black), _describe_engine(engine_white)
	])
	var LocalAIPlayer = load("res://scripts/player/local_ai_player.gd")
	var ai_b = LocalAIPlayer.new(engine_black)
	ai_b.color = _GameLogic.BLACK
	var ai_w = LocalAIPlayer.new(engine_white)
	ai_w.color = _GameLogic.WHITE
	players[0] = ai_b
	players[1] = ai_w
	_disconnect_network_signals()


func _describe_engine(engine) -> String:
	if engine == null:
		return "null"
	var script = engine.get_script() if engine.has_method("get_script") else null
	var path: String = str(script.resource_path) if script != null else "no-script"
	var name: String = engine.get_name() if engine.has_method("get_name") else "<no-get_name>"
	return "%s[%s]" % [path, name]


# ---- Core game loop ----

func start_game() -> void:
	logic.reset()
	logic.forbidden_enabled = forbidden_enabled
	_apply_ai_ruleset()
	var mode_names: Array[String] = ["online", "local_pvp", "vs_ai", "ai_vs_ai"]
	var mode_name: String = mode_names[mode]
	Log.info("Game", "start mode=%s black=%s white=%s" % [
		mode_name, _get_player_type_string(0), _get_player_type_string(1)
	])
	game_reset.emit()
	_update_turn_state()
	_request_current_move()


func submit_human_move(row: int, col: int) -> void:
	var ctrl = _current_controller()
	if ctrl.player_type == _PlayerController.Type.LOCAL_HUMAN:
		ctrl.submit_move(row, col)


func _request_current_move() -> void:
	var ctrl = _current_controller()
	# Bracket each request with a "thinking" log so we can see how long
	# a GDScript AI (L1-L4) spends choosing a move — previously their
	# turns were invisible between request and _on_move_decided.
	Log.info("Turn", "move %d: %s thinking (%s to play)" % [
		logic.move_history.size() + 1,
		_get_player_type_string(_color_index(logic.current_player)),
		"BLACK" if logic.current_player == _GameLogic.BLACK else "WHITE"
	])
	if not ctrl.move_decided.is_connected(_on_move_decided):
		ctrl.move_decided.connect(_on_move_decided, CONNECT_ONE_SHOT)
	ctrl.request_move(logic.board, logic.current_player, logic.move_history)


var _invalid_retries: int = 0


func _on_move_decided(row: int, col: int) -> void:
	var color: int = logic.current_player
	# One line per move regardless of source (human, GDScript L1-L4, or
	# the Swift plugin) so the log is a full transcript. Previously only
	# plugin-routed L5/L6 logged, which hid stalls in GDScript AIs and
	# made mystery (1,1)-type moves impossible to contextualise.
	Log.info("Move", "%d→(%d,%d) by %s" % [
		logic.move_history.size() + 1, row, col,
		_get_player_type_string(_color_index(color))
	])

	if not logic.place_stone(row, col):
		# Invalid move. An AI that keeps returning the same (0,0) caused
		# the "stuck game" bug in the user's log — we'd re-request the
		# same engine, it'd return (0,0) again, infinite loop filling
		# the log. Cap the retries and log the identity of the misbehaving
		# engine so we can debug it next session.
		_invalid_retries += 1
		var ctrl = _current_controller()
		var engine_info: String = "unknown"
		if ctrl and "ai_engine" in ctrl and ctrl.ai_engine != null:
			engine_info = str(ctrl.ai_engine.get_script().resource_path) \
				if ctrl.ai_engine.get_script() != null else "no-script"
		Log.warn("Move", "invalid move (%d,%d) retry=%d engine=%s" % [
			row, col, _invalid_retries, engine_info
		])
		if _invalid_retries >= 3:
			# Fallback: pick any legal move so the game doesn't freeze.
			var legal = _first_empty_cell()
			_invalid_retries = 0
			if legal.x >= 0:
				Log.warn("Move", "AI stuck, falling back to (%d,%d)" % [legal.x, legal.y])
				_on_move_decided(legal.x, legal.y)
			else:
				Log.error("Move", "no legal move, ending game")
				logic.game_over = true
				game_ended.emit(0)
			return
		_request_current_move()
		return
	_invalid_retries = 0

	stone_placed.emit(row, col, color)

	# If online, send move to remote peer
	if mode == GameMode.ONLINE:
		var ctrl = players[_color_index(color)]
		if ctrl.player_type == _PlayerController.Type.LOCAL_HUMAN:
			NetworkManager.send_move(row, col)

	if logic.game_over:
		Log.info("Game", "end winner=%d moves=%d" % [logic.winner, logic.move_history.size()])
		_save_game_record()
		game_ended.emit(logic.winner)
	else:
		_update_turn_state()
		if mode == GameMode.AI_VS_AI and ai_move_delay > 0.0:
			await get_tree().create_timer(ai_move_delay).timeout
		_request_current_move()


# ---- Turn state ----

func _update_turn_state() -> void:
	var ctrl = _current_controller()
	match mode:
		GameMode.ONLINE, GameMode.VS_AI:
			is_my_turn = (ctrl.player_type == _PlayerController.Type.LOCAL_HUMAN)
			turn_changed.emit(is_my_turn)
		GameMode.LOCAL_PVP:
			is_my_turn = true  # always a local human's turn
			turn_changed.emit(true)
		GameMode.AI_VS_AI:
			is_my_turn = false
			turn_changed.emit(false)


# ---- Reset / Play Again ----

func request_reset() -> void:
	if mode == GameMode.ONLINE:
		NetworkManager.send_reset_request()
	else:
		# Non-network modes: just restart
		_cancel_current_move()
		start_game()


func accept_reset() -> void:
	if mode == GameMode.ONLINE:
		NetworkManager.send_reset_accept()
	_cancel_current_move()
	start_game()


func _on_reset_requested() -> void:
	opponent_reset_requested.emit()


func _on_reset_accepted() -> void:
	_cancel_current_move()
	start_game()


# ---- Helpers ----

func _current_controller():
	return players[_color_index(logic.current_player)]


func _color_index(color: int) -> int:
	return 0 if color == _GameLogic.BLACK else 1


func _apply_ai_ruleset() -> void:
	for p in players:
		if p != null and "ai_engine" in p and p.ai_engine != null:
			if "forbidden_enabled" in p.ai_engine:
				p.ai_engine.forbidden_enabled = forbidden_enabled


func _first_empty_cell() -> Vector2i:
	for r in range(_GameLogic.BOARD_SIZE):
		for c in range(_GameLogic.BOARD_SIZE):
			if logic.board[r][c] == _GameLogic.EMPTY and not logic.is_forbidden_move(r, c, logic.current_player):
				return Vector2i(r, c)
	return Vector2i(-1, -1)


func _cancel_current_move() -> void:
	for p in players:
		if p != null:
			if p.move_decided.is_connected(_on_move_decided):
				p.move_decided.disconnect(_on_move_decided)
			p.cancel()


func _get_player_type_string(player_idx: int) -> String:
	var p = players[player_idx]
	if p == null:
		return "unknown"
	match p.player_type:
		_PlayerController.Type.LOCAL_HUMAN:
			return "human"
		_PlayerController.Type.REMOTE_NETWORK:
			return "network"
		_PlayerController.Type.LOCAL_AI:
			if p.ai_engine != null and p.ai_engine.has_method("get_name"):
				return "ai_" + p.ai_engine.get_name().to_lower()
			return "ai"
		_:
			return "unknown"


func _save_game_record() -> void:
	var GameRecord = load("res://scripts/data/game_record.gd")
	var record = GameRecord.new()
	record.timestamp = Time.get_datetime_string_from_system().replace("T", "_").replace(":", "-")
	match mode:
		GameMode.ONLINE: record.mode = "online"
		GameMode.LOCAL_PVP: record.mode = "local_pvp"
		GameMode.VS_AI: record.mode = "vs_ai"
		GameMode.AI_VS_AI: record.mode = "ai_vs_ai"
	record.black_type = _get_player_type_string(0)
	record.white_type = _get_player_type_string(1)
	record.result = logic.winner
	record.total_moves = logic.move_history.size()
	for m in logic.move_history:
		record.moves.append([m.x, m.y])
	var path = GameRecord.get_records_dir() + "/" + record.timestamp + ".json"
	GameRecord.save_to_file(record, path)


func _disconnect_network_signals() -> void:
	if NetworkManager.reset_requested.is_connected(_on_reset_requested):
		NetworkManager.reset_requested.disconnect(_on_reset_requested)
	if NetworkManager.reset_accepted.is_connected(_on_reset_accepted):
		NetworkManager.reset_accepted.disconnect(_on_reset_accepted)
