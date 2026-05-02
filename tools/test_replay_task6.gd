extends Node

const GameLogic = preload("res://scripts/game_logic.gd")
const GameRecord = preload("res://scripts/data/game_record.gd")

var failures: Array[String] = []
var temp_path: String = "user://task6_replay_test_record.json"


func _ready() -> void:
	await _run_tests()
	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(temp_path)
	if failures.is_empty():
		print("REPLAY_TASK6_TESTS PASS")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)


func _run_tests() -> void:
	_test_load_from_file_missing_returns_null()
	_test_load_from_file_invalid_json_returns_null()
	_test_load_from_file_parseable_malformed_json_returns_null()
	_test_prepare_replay_from_last_game_uses_saved_record()
	_test_start_game_clears_stale_last_game_record()
	_test_save_game_record_failure_clears_stale_last_game_record()
	_test_prepare_replay_from_path_loads_record()
	await _test_replay_scene_loads_and_controls_render_board()
	await _test_replay_scene_handles_no_record_and_empty_moves()


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _assert_false(condition: bool, message: String) -> void:
	if condition:
		failures.append(message)


func _assert_eq(actual, expected, message: String) -> void:
	if actual != expected:
		failures.append("%s expected=%s actual=%s" % [message, str(expected), str(actual)])


func _make_record() -> Variant:
	var record = GameRecord.new()
	record.timestamp = "task6-test"
	record.mode = "local_pvp"
	record.black_type = "human"
	record.white_type = "human"
	record.ruleset = "free"
	record.result = GameLogic.BLACK
	record.moves = [[7, 7], [7, 8], [8, 8]]
	record.total_moves = record.moves.size()
	return record


func _test_load_from_file_missing_returns_null() -> void:
	var missing = GameRecord.load_from_file("user://missing_task6_replay_record.json")
	_assert_true(missing == null, "missing record path should return null")


func _test_load_from_file_invalid_json_returns_null() -> void:
	var file = FileAccess.open(temp_path, FileAccess.WRITE)
	file.store_string("{not valid json")
	file.close()
	var loaded = GameRecord.load_from_file(temp_path)
	_assert_true(loaded == null, "invalid JSON record should return null")


func _test_load_from_file_parseable_malformed_json_returns_null() -> void:
	var malformed_records: Array[String] = [
		"[]",
		"{\"moves\":\"not-array\",\"result\":1}",
		"{\"moves\":[[7]],\"result\":1}",
		"{\"moves\":[[7,\"x\"]],\"result\":1}",
		"{\"moves\":[[7,8]],\"result\":3}",
		"{\"moves\":[[7,8]],\"result\":1,\"total_moves\":\"one\"}",
		"{\"moves\":[[7,8]],\"result\":1,\"ruleset\":\"freestyle\"}",
	]
	for text in malformed_records:
		var file = FileAccess.open(temp_path, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		var loaded = GameRecord.load_from_file(temp_path)
		_assert_true(loaded == null, "parseable malformed record should return null: %s" % text)


func _test_prepare_replay_from_last_game_uses_saved_record() -> void:
	var gm = get_node("/root/GameManager")
	_assert_true("last_game_record" in gm, "GameManager should expose last_game_record")
	_assert_true("replay_record" in gm, "GameManager should expose replay_record")
	_assert_true(gm.has_method("prepare_replay_from_last_game"), "GameManager should prepare replay from last game")
	if not ("last_game_record" in gm and "replay_record" in gm and gm.has_method("prepare_replay_from_last_game")):
		return
	gm.last_game_record = _make_record()
	gm.replay_record = null
	var ok: bool = gm.prepare_replay_from_last_game()
	_assert_true(ok, "prepare_replay_from_last_game should succeed when last record exists")
	_assert_true(gm.replay_record == gm.last_game_record, "prepare_replay_from_last_game should assign replay_record")
	gm.last_game_record = null
	gm.replay_record = _make_record()
	ok = gm.prepare_replay_from_last_game()
	_assert_false(ok, "prepare_replay_from_last_game should fail cleanly without last record")
	_assert_true(gm.replay_record == null, "prepare_replay_from_last_game should clear stale replay_record on failure")


func _test_start_game_clears_stale_last_game_record() -> void:
	var gm = get_node("/root/GameManager")
	if not ("last_game_record" in gm):
		_assert_true(false, "GameManager should expose last_game_record")
		return
	gm.setup_local_pvp(false)
	gm.last_game_record = _make_record()
	gm.start_game()
	_assert_true(gm.last_game_record == null, "start_game should clear stale last_game_record")
	gm.pause_current_move()


func _test_save_game_record_failure_clears_stale_last_game_record() -> void:
	var gm = get_node("/root/GameManager")
	if not ("last_game_record" in gm and gm.has_method("_save_game_record")):
		_assert_true(false, "GameManager should expose last_game_record and _save_game_record")
		return
	gm.setup_local_pvp(false)
	gm.start_game()
	gm.pause_current_move()
	gm.last_game_record = _make_record()
	gm.logic.winner = GameLogic.BLACK
	gm.logic.move_history.clear()
	gm.logic.move_history.append(Vector2i(7, 7))
	gm._save_game_record("/proc/task6_replay_record_should_not_save.json")
	_assert_true(gm.last_game_record == null, "failed save should clear stale last_game_record")


func _test_prepare_replay_from_path_loads_record() -> void:
	var record = _make_record()
	_assert_true(GameRecord.save_to_file(record, temp_path), "fixture record should save")
	var gm = get_node("/root/GameManager")
	_assert_true("replay_record" in gm, "GameManager should expose replay_record for path replay")
	_assert_true(gm.has_method("prepare_replay_from_path"), "GameManager should prepare replay from path")
	if not ("replay_record" in gm and gm.has_method("prepare_replay_from_path")):
		return
	gm.replay_record = null
	var ok: bool = gm.prepare_replay_from_path(temp_path)
	_assert_true(ok, "prepare_replay_from_path should succeed for saved record")
	_assert_true(gm.replay_record != null, "prepare_replay_from_path should set replay_record")
	_assert_eq(gm.replay_record.moves.size(), 3, "loaded replay record should preserve moves")
	ok = gm.prepare_replay_from_path("user://missing_task6_replay_record.json")
	_assert_false(ok, "prepare_replay_from_path should fail for missing path")
	_assert_true(gm.replay_record == null, "prepare_replay_from_path should clear stale replay_record on failure")


func _test_replay_scene_loads_and_controls_render_board() -> void:
	var gm = get_node("/root/GameManager")
	_assert_true("replay_record" in gm, "GameManager should expose replay_record for replay scene")
	if not ("replay_record" in gm):
		return
	gm.replay_record = _make_record()
	var scene: PackedScene = load("res://scenes/replay/replay.tscn")
	_assert_true(scene != null, "replay scene should load")
	if scene == null:
		return
	var replay = scene.instantiate()
	add_child(replay)
	await get_tree().process_frame
	_assert_eq(replay.cursor, gm.replay_record.moves.size(), "replay scene should start at final move")
	_assert_true("read_only" in replay.board, "board should expose read_only replay guard")
	_assert_true("display_board" in replay.board, "board should expose display_board for replay rendering")
	_assert_true("display_last_move" in replay.board, "board should expose display_last_move for replay marker")
	if "read_only" in replay.board:
		_assert_true(replay.board.read_only, "replay scene should mark board read-only")
		_assert_eq(replay.board.hover_pos, Vector2i(-1, -1), "read-only replay board should not show hover previews")
	if "display_board" in replay.board and "display_last_move" in replay.board:
		_assert_eq(replay.board.display_board[7][7], GameLogic.BLACK, "replay scene should render first black move via board display state")
		_assert_eq(replay.board.display_board[7][8], GameLogic.WHITE, "replay scene should render second white move via board display state")
		_assert_eq(replay.board.display_board[8][8], GameLogic.BLACK, "replay scene should render third black move via board display state")
		_assert_eq(replay.board.display_last_move, Vector2i(8, 8), "replay scene should mark visible last move")
	replay._on_start_pressed()
	_assert_eq(replay.cursor, 0, "start control should reset cursor")
	if "display_board" in replay.board and "display_last_move" in replay.board:
		_assert_eq(replay.board.display_board[7][7], GameLogic.EMPTY, "start control should clear board display state")
		_assert_eq(replay.board.display_last_move, Vector2i(-1, -1), "start control should clear last move marker")
		_assert_true(replay.board.has_method("_active_last_move"), "board should expose active last move helper")
		if replay.board.has_method("_active_last_move"):
			_assert_eq(replay.board._active_last_move(), Vector2i(-1, -1), "empty replay display should not fall back to live game last move")
	replay._on_next_pressed()
	_assert_eq(replay.cursor, 1, "next control should advance cursor")
	if "display_board" in replay.board and "display_last_move" in replay.board:
		_assert_eq(replay.board.display_board[7][7], GameLogic.BLACK, "next control should render first move via board display state")
		_assert_eq(replay.board.display_last_move, Vector2i(7, 7), "next control should mark first move")
	replay._on_prev_pressed()
	_assert_eq(replay.cursor, 0, "previous control should decrement cursor")
	if "display_board" in replay.board and "display_last_move" in replay.board:
		_assert_eq(replay.board.display_board[7][7], GameLogic.EMPTY, "previous control should remove last visible move from board display state")
		_assert_eq(replay.board.display_last_move, Vector2i(-1, -1), "previous control should clear last move marker")
	replay.queue_free()


func _test_replay_scene_handles_no_record_and_empty_moves() -> void:
	var gm = get_node("/root/GameManager")
	if not ("replay_record" in gm):
		_assert_true(false, "GameManager should expose replay_record for replay scene")
		return
	var scene: PackedScene = load("res://scenes/replay/replay.tscn")
	_assert_true(scene != null, "replay scene should load for empty state tests")
	if scene == null:
		return
	gm.replay_record = null
	var no_record_replay = scene.instantiate()
	add_child(no_record_replay)
	await get_tree().process_frame
	_assert_eq(no_record_replay.cursor, 0, "no-record replay should start at cursor zero")
	_assert_true(no_record_replay.prev_button.disabled, "no-record replay should disable previous")
	_assert_true(no_record_replay.start_button.disabled, "no-record replay should disable start")
	_assert_true(no_record_replay.next_button.disabled, "no-record replay should disable next")
	_assert_true(no_record_replay.play_button.disabled, "no-record replay should disable play")
	no_record_replay.queue_free()

	var empty_record = _make_record()
	empty_record.moves = []
	empty_record.total_moves = 0
	gm.replay_record = empty_record
	var empty_replay = scene.instantiate()
	add_child(empty_replay)
	await get_tree().process_frame
	_assert_eq(empty_replay.cursor, 0, "empty replay should start at cursor zero")
	_assert_true(empty_replay.prev_button.disabled, "empty replay should disable previous")
	_assert_true(empty_replay.start_button.disabled, "empty replay should disable start")
	_assert_true(empty_replay.next_button.disabled, "empty replay should disable next")
	_assert_true(empty_replay.play_button.disabled, "empty replay should disable play")
	empty_replay.queue_free()
