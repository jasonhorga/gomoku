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
	_test_prepare_replay_from_last_game_uses_saved_record()
	_test_prepare_replay_from_path_loads_record()
	await _test_replay_scene_loads_and_controls_render_board()


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
	_assert_eq(replay.replay_board[7][7], GameLogic.BLACK, "replay scene should render first black move")
	_assert_eq(replay.replay_board[7][8], GameLogic.WHITE, "replay scene should render second white move")
	_assert_eq(replay.replay_board[8][8], GameLogic.BLACK, "replay scene should render third black move")
	replay._on_start_pressed()
	_assert_eq(replay.cursor, 0, "start control should reset cursor")
	_assert_eq(replay.replay_board[7][7], GameLogic.EMPTY, "start control should clear board")
	replay._on_next_pressed()
	_assert_eq(replay.cursor, 1, "next control should advance cursor")
	_assert_eq(replay.replay_board[7][7], GameLogic.BLACK, "next control should render first move")
	replay._on_prev_pressed()
	_assert_eq(replay.cursor, 0, "previous control should decrement cursor")
	_assert_eq(replay.replay_board[7][7], GameLogic.EMPTY, "previous control should remove last visible move")
	replay.queue_free()
