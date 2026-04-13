extends SceneTree

const BOARD_SIZE: int = 15
const EMPTY: int = 0
const BLACK: int = 1
const WHITE: int = 2

var tests_passed: int = 0
var tests_failed: int = 0


func _init() -> void:
	print("=== Phase 3 Unit Tests: Advanced AI ===\n")

	test_zobrist()
	test_minimax_depth4_win()
	test_minimax_depth4_block()
	test_mcts_win()
	test_mcts_block()

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


func test_zobrist() -> void:
	print("[Zobrist]")
	var z = load("res://scripts/ai/zobrist.gd").new()
	z.reset()
	var h0: int = z.get_hash()
	assert_eq(h0, 0, "initial hash is 0")

	z.update(7, 7, BLACK)
	var h1: int = z.get_hash()
	assert_true(h1 != 0, "hash changes after update")

	z.update(7, 7, BLACK)  # XOR same value again
	assert_eq(z.get_hash(), 0, "hash returns to 0 after undo")


func test_minimax_depth4_win() -> void:
	print("[Minimax depth 4 - win]")
	var ai = load("res://scripts/ai/ai_minimax.gd").new(4)
	var board = _make_board()

	# Black has 4 in a row — must find the win
	board[5][3] = BLACK
	board[5][4] = BLACK
	board[5][5] = BLACK
	board[5][6] = BLACK
	board[6][3] = WHITE
	board[6][4] = WHITE
	board[6][5] = WHITE

	var start = Time.get_ticks_msec()
	var move = ai.choose_move(board, BLACK, [])
	var elapsed = Time.get_ticks_msec() - start

	var wins = (move == Vector2i(5, 7) or move == Vector2i(5, 2))
	assert_true(wins, "depth-4 finds winning move at %s" % str(move))
	print("  INFO: depth-4 took %d ms" % elapsed)


func test_minimax_depth4_block() -> void:
	print("[Minimax depth 4 - block]")
	var ai = load("res://scripts/ai/ai_minimax.gd").new(4)
	var board = _make_board()

	board[3][3] = WHITE
	board[3][4] = WHITE
	board[3][5] = WHITE
	board[3][6] = WHITE
	board[4][4] = BLACK
	board[4][5] = BLACK

	var start = Time.get_ticks_msec()
	var move = ai.choose_move(board, BLACK, [])
	var elapsed = Time.get_ticks_msec() - start

	var blocks = (move == Vector2i(3, 7) or move == Vector2i(3, 2))
	assert_true(blocks, "depth-4 blocks at %s" % str(move))
	print("  INFO: depth-4 block took %d ms" % elapsed)


func test_mcts_win() -> void:
	print("[MCTS - win]")
	var ai = load("res://scripts/ai/ai_mcts.gd").new(500)  # fewer sims for test speed
	var board = _make_board()

	board[5][3] = BLACK
	board[5][4] = BLACK
	board[5][5] = BLACK
	board[5][6] = BLACK
	board[6][3] = WHITE
	board[6][4] = WHITE
	board[6][5] = WHITE

	var start = Time.get_ticks_msec()
	var move = ai.choose_move(board, BLACK, [])
	var elapsed = Time.get_ticks_msec() - start

	var wins = (move == Vector2i(5, 7) or move == Vector2i(5, 2))
	assert_true(wins, "MCTS finds winning move at %s" % str(move))
	print("  INFO: MCTS(500) took %d ms" % elapsed)


func test_mcts_block() -> void:
	print("[MCTS - block]")
	var ai = load("res://scripts/ai/ai_mcts.gd").new(500)
	var board = _make_board()

	board[3][3] = WHITE
	board[3][4] = WHITE
	board[3][5] = WHITE
	board[3][6] = WHITE
	board[4][4] = BLACK
	board[4][5] = BLACK

	var start = Time.get_ticks_msec()
	var move = ai.choose_move(board, BLACK, [])
	var elapsed = Time.get_ticks_msec() - start

	var blocks = (move == Vector2i(3, 7) or move == Vector2i(3, 2))
	assert_true(blocks, "MCTS blocks at %s" % str(move))
	print("  INFO: MCTS(500) block took %d ms" % elapsed)
