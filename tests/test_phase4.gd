extends SceneTree

const BOARD_SIZE: int = 15
const EMPTY: int = 0
const BLACK: int = 1
const WHITE: int = 2

var tests_passed: int = 0
var tests_failed: int = 0


func _init() -> void:
	print("=== Phase 4 Unit Tests: Records + Weight Tuning ===\n")

	test_game_record_serialization()
	test_ai_vs_ai_game()
	test_weight_tuner()

	print("\n=== Results: %d passed, %d failed ===" % [tests_passed, tests_failed])
	if tests_failed > 0:
		quit(1)
	else:
		quit(0)


func assert_true(val: bool, msg: String) -> void:
	if val:
		tests_passed += 1
		print("  PASS: %s" % msg)
	else:
		tests_failed += 1
		print("  FAIL: %s" % msg)


func assert_eq(actual, expected, msg: String) -> void:
	if actual == expected:
		tests_passed += 1
		print("  PASS: %s" % msg)
	else:
		tests_failed += 1
		print("  FAIL: %s (expected %s, got %s)" % [msg, str(expected), str(actual)])


func _make_board() -> Array:
	var board: Array = []
	for r in range(BOARD_SIZE):
		var row: Array = []
		row.resize(BOARD_SIZE)
		row.fill(EMPTY)
		board.append(row)
	return board


func test_game_record_serialization() -> void:
	print("[GameRecord]")
	var GR = load("res://scripts/data/game_record.gd")
	var record = GR.new()
	record.timestamp = "2026-04-10"
	record.mode = "vs_ai"
	record.black_type = "human"
	record.white_type = "ai_heuristic"
	record.moves = [[7,7], [8,8], [7,8]]
	record.result = BLACK
	record.total_moves = 3

	var json_str = record.to_json()
	assert_true(json_str.length() > 10, "to_json produces output")

	var restored = GR.from_json(json_str)
	assert_true(restored != null, "from_json returns record")
	assert_eq(restored.mode, "vs_ai", "mode preserved")
	assert_eq(restored.result, BLACK, "result preserved")
	assert_eq(restored.moves.size(), 3, "moves preserved")
	assert_eq(restored.black_type, "human", "black_type preserved")


func test_ai_vs_ai_game() -> void:
	print("[AI vs AI game]")
	var logic = load("res://scripts/game_logic.gd").new()
	var ai_b = load("res://scripts/ai/ai_heuristic.gd").new()
	var ai_w = load("res://scripts/ai/ai_heuristic.gd").new()

	var current = BLACK
	var move_count: int = 0

	while not logic.game_over and move_count < 225:
		var board_copy: Array = []
		for row in logic.board:
			board_copy.append(row.duplicate())

		var move: Vector2i
		if current == BLACK:
			move = ai_b.choose_move(board_copy, current, logic.move_history.duplicate())
		else:
			move = ai_w.choose_move(board_copy, current, logic.move_history.duplicate())

		var ok = logic.place_stone(move.x, move.y)
		assert_true(ok or move_count > 200, "move %d valid at %s" % [move_count, str(move)])
		if not ok:
			break
		current = WHITE if current == BLACK else BLACK
		move_count += 1

	assert_true(logic.game_over, "AI vs AI game ends (moves: %d)" % move_count)
	assert_true(logic.winner != -1, "game has a result: %d" % logic.winner)
	print("  INFO: game ended in %d moves, winner=%d" % [move_count, logic.winner])


func test_weight_tuner() -> void:
	print("[WeightTuner]")
	var GR = load("res://scripts/data/game_record.gd")
	var WT = load("res://scripts/data/weight_tuner.gd")
	var PE = load("res://scripts/ai/pattern_evaluator.gd")

	# Create a fake record where black wins
	var record = GR.new()
	record.mode = "ai_vs_ai"
	record.black_type = "ai_heuristic"
	record.white_type = "ai_heuristic"
	record.result = BLACK
	record.total_moves = 9
	record.moves = [[7,7], [8,8], [7,8], [8,7], [7,6], [8,6], [7,5], [8,5], [7,4]]

	var eval = PE.new()
	var original_weights = eval.weights.duplicate()

	var tuner = WT.new()
	var new_weights = tuner.tune_from_records([record], original_weights)

	# Weights should change (at least slightly)
	var changed: bool = false
	for key in new_weights:
		if absf(new_weights[key] - original_weights[key]) > 0.001:
			changed = true
			break

	assert_true(changed, "weights changed after tuning")

	# Verify weights are still reasonable (positive)
	var all_positive: bool = true
	for key in new_weights:
		if new_weights[key] < 1.0:
			all_positive = false
	assert_true(all_positive, "all weights remain positive")
	print("  INFO: sample weight changes:")
	for key in new_weights:
		var diff = new_weights[key] - original_weights[key]
		if absf(diff) > 0.001:
			print("    %s: %.1f -> %.1f (%+.1f)" % [key, original_weights[key], new_weights[key], diff])
