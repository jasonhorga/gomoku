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

signal stone_placed(row: int, col: int, color: int)
signal turn_changed(is_my_turn: bool)
signal game_ended(winner: int)
signal opponent_reset_requested()
signal game_reset()


func _ready() -> void:
	# P2b smoke test — on iOS TestFlight builds this is how we confirm
	# the GomokuNeural plugin (Swift + CoreML wrapper) loaded and can
	# be called from GDScript. The "hardcoded (7,7)" response will be
	# replaced with real inference in P2f. Platforms without the plugin
	# (Linux editor, Mac dev builds) silently skip.
	_smoke_test_plugin()


func _smoke_test_plugin() -> void:
	if not Engine.has_singleton("GomokuNeural"):
		Log.info("Plugin", "GomokuNeural not present (OK on %s)" % OS.get_name())
		return
	var plugin = Engine.get_singleton("GomokuNeural")
	var version: String = plugin.plugin_version()
	var move: Vector2i = plugin.get_move(6, [], 1, Vector2i(-1, -1))
	Log.info("Plugin", "GomokuNeural loaded: %s, test move=(%d,%d)" % [version, move.x, move.y])


# ---- Setup methods (call before entering game scene) ----

func setup_online(player_color: int) -> void:
	mode = GameMode.ONLINE
	my_color = player_color
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


func setup_local_pvp() -> void:
	mode = GameMode.LOCAL_PVP
	my_color = -1  # both are local
	var p1 = load("res://scripts/player/human_player.gd").new()
	p1.color = _GameLogic.BLACK
	var p2 = load("res://scripts/player/human_player.gd").new()
	p2.color = _GameLogic.WHITE
	players[0] = p1
	players[1] = p2
	_disconnect_network_signals()


func setup_vs_ai(human_color: int, ai_engine) -> void:
	mode = GameMode.VS_AI
	my_color = human_color
	var human = load("res://scripts/player/human_player.gd").new()
	human.color = human_color
	# ai_engine: an AIEngine instance, will be wrapped in LocalAIPlayer
	var LocalAIPlayer = load("res://scripts/player/local_ai_player.gd")
	var ai = LocalAIPlayer.new(ai_engine)
	ai.color = _GameLogic.WHITE if human_color == _GameLogic.BLACK else _GameLogic.BLACK
	players[_color_index(human_color)] = human
	players[_color_index(ai.color)] = ai
	_disconnect_network_signals()


func setup_ai_vs_ai(engine_black, engine_white) -> void:
	mode = GameMode.AI_VS_AI
	my_color = -1
	var LocalAIPlayer = load("res://scripts/player/local_ai_player.gd")
	var ai_b = LocalAIPlayer.new(engine_black)
	ai_b.color = _GameLogic.BLACK
	var ai_w = LocalAIPlayer.new(engine_white)
	ai_w.color = _GameLogic.WHITE
	players[0] = ai_b
	players[1] = ai_w
	_disconnect_network_signals()


# ---- Core game loop ----

func start_game() -> void:
	logic.reset()
	var mode_name := ["online", "local_pvp", "vs_ai", "ai_vs_ai"][mode]
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
	if not ctrl.move_decided.is_connected(_on_move_decided):
		ctrl.move_decided.connect(_on_move_decided, CONNECT_ONE_SHOT)
	ctrl.request_move(logic.board, logic.current_player, logic.move_history)


func _on_move_decided(row: int, col: int) -> void:
	var color: int = logic.current_player

	if not logic.place_stone(row, col):
		# Invalid move — re-request
		_request_current_move()
		return

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
