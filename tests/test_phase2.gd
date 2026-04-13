extends SceneTree

const BOARD_SIZE: int = 15
const EMPTY: int = 0
const BLACK: int = 1
const WHITE: int = 2

var tests_passed: int = 0
var tests_failed: int = 0


func _init() -> void:
	print("=== Phase 2 Unit Tests: AI Engines ===\n")

	test_ai_random()
	test_pattern_evaluator_basics()
	test_pattern_evaluator_blocking()
	test_ai_heuristic()
	test_ai_minimax_wins()
	test_ai_minimax_blocks()

	print("\n=== Results: %d passed, %d failed ===" % [tests_passed, tests_failed])
	if tests_failed > 0:
		quit(1)
	else:
		quit(0)


func assert_eq(actual, expected, msg: String) -> void:
	if actual == expected:
		tests_passed += 1
		print("  PASS: %s" % msg)
	else:
		tests_failed += 1
		print("  FAIL: %s (expected %s, got %s)" % [msg, str(expected), str(actual)])


func assert_true(val: bool, msg: String) -> void:
	assert_eq(val, true, msg)


func _make_board() -> Array:
	var board: Array = []
	for r in range(BOARD_SIZE):
		var row: Array = []
		row.resize(BOARD_SIZE)
		row.fill(EMPTY)
		board.append(row)
	return board


func test_ai_random() -> void:
	print("[AI Random]")
	var ai = load("res://scripts/ai/ai_random.gd").new()
	var board = _make_board()

	# Empty board: should play center area
	var move = ai.choose_move(board, BLACK, [])
	assert_eq(move, Vector2i(7, 7), "random AI plays center on empty board")

	# Board with some stones: should play near them
	board[7][7] = BLACK
	board[7][8] = WHITE
	move = ai.choose_move(board, BLACK, [Vector2i(7,7), Vector2i(7,8)])
	assert_true(move.x >= 0 and move.x < BOARD_SIZE, "random AI returns valid row")
	assert_true(board[move.x][move.y] == EMPTY, "random AI picks empty cell")


func test_pattern_evaluator_basics() -> void:
	print("[PatternEvaluator]")
	var eval = load("res://scripts/ai/pattern_evaluator.gd").new()
	var board = _make_board()

	# Place 4 black in a row with open end → should score high for completing
	board[7][3] = BLACK
	board[7][4] = BLACK
	board[7][5] = BLACK
	board[7][6] = BLACK
	# Scoring cell (7,7) for BLACK should detect open_four or five
	var score = eval.score_cell(board, 7, 7, BLACK)
	assert_true(score >= 10000, "4-in-a-row + empty = very high score (got %d)" % int(score))

	# Scoring cell (7,2) for BLACK (other open end)
	var score2 = eval.score_cell(board, 7, 2, BLACK)
	assert_true(score2 >= 10000, "other end of 4-in-a-row also high")


func test_pattern_evaluator_blocking() -> void:
	print("[PatternEvaluator blocking]")
	var eval = load("res://scripts/ai/pattern_evaluator.gd").new()
	var board = _make_board()

	# Black has 4 in a row, WHITE should also want to block at (7,7)
	board[7][3] = BLACK
	board[7][4] = BLACK
	board[7][5] = BLACK
	board[7][6] = BLACK

	var score_white = eval.score_cell(board, 7, 7, WHITE)
	assert_true(score_white > 1000, "white scores high blocking black's 4 (got %d)" % int(score_white))


func test_ai_heuristic() -> void:
	print("[AI Heuristic]")
	var ai = load("res://scripts/ai/ai_heuristic.gd").new()
	var board = _make_board()

	# Black has 4 in a row — AI (as black) should complete the win
	board[7][3] = BLACK
	board[7][4] = BLACK
	board[7][5] = BLACK
	board[7][6] = BLACK

	var move = ai.choose_move(board, BLACK, [])
	var wins = (move == Vector2i(7, 7) or move == Vector2i(7, 2))
	assert_true(wins, "heuristic AI completes 5-in-a-row at %s" % str(move))

	# White should block
	var move_w = ai.choose_move(board, WHITE, [])
	var blocks = (move_w == Vector2i(7, 7) or move_w == Vector2i(7, 2))
	assert_true(blocks, "heuristic AI blocks at %s" % str(move_w))


func test_ai_minimax_wins() -> void:
	print("[AI Minimax - win]")
	var ai = load("res://scripts/ai/ai_minimax.gd").new(2)
	var board = _make_board()

	# Black has 4 in a row — minimax should find the winning move
	board[5][3] = BLACK
	board[5][4] = BLACK
	board[5][5] = BLACK
	board[5][6] = BLACK
	board[6][3] = WHITE
	board[6][4] = WHITE
	board[6][5] = WHITE

	var move = ai.choose_move(board, BLACK, [])
	var wins = (move == Vector2i(5, 7) or move == Vector2i(5, 2))
	assert_true(wins, "minimax finds winning move at %s" % str(move))


func test_ai_minimax_blocks() -> void:
	print("[AI Minimax - block]")
	var ai = load("res://scripts/ai/ai_minimax.gd").new(2)
	var board = _make_board()

	# White has 4 in a row — black (minimax) should block
	board[3][3] = WHITE
	board[3][4] = WHITE
	board[3][5] = WHITE
	board[3][6] = WHITE
	board[4][4] = BLACK
	board[4][5] = BLACK

	var move = ai.choose_move(board, BLACK, [])
	var blocks = (move == Vector2i(3, 7) or move == Vector2i(3, 2))
	assert_true(blocks, "minimax blocks opponent's 4 at %s" % str(move))
