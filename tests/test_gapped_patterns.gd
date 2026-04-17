extends SceneTree

const PatternEvaluator = preload("res://scripts/ai/pattern_evaluator.gd")
const BOARD_SIZE = 15
const EMPTY = 0
const BLACK = 1
const WHITE = 2


func _init():
	var evaluator = PatternEvaluator.new()
	var passed = 0
	var failed = 0

	# Helper: make empty board
	var board = []
	for i in range(BOARD_SIZE):
		var row = []
		for _j in range(BOARD_SIZE):
			row.append(EMPTY)
		board.append(row)

	# Test 1: Split-three recognition — XX_X creates half_three threat
	# Place BLACK at (7,5), (7,6), (7,8) — evaluating empty (7,7)
	board[7][5] = BLACK
	board[7][6] = BLACK
	board[7][8] = BLACK
	var score_fill_gap = evaluator._evaluate_position(board, 7, 7, BLACK)
	# Filling the gap creates 4-in-a-row with 2 open ends (open_four = 10000)
	print("Test 1 — fill split-three gap: score=%f (expect ~10000 open_four)" % score_fill_gap)
	if score_fill_gap >= 10000:
		passed += 1
	else:
		failed += 1
	# Reset
	board[7][5] = EMPTY
	board[7][6] = EMPTY
	board[7][8] = EMPTY

	# Test 2: Split-four recognition — XXX_X means placing at gap creates five
	board[7][5] = BLACK
	board[7][6] = BLACK
	board[7][7] = BLACK
	board[7][9] = BLACK
	var score_fill_split4 = evaluator._evaluate_position(board, 7, 8, BLACK)
	print("Test 2 — fill split-four gap: score=%f (expect 100000 five)" % score_fill_split4)
	if score_fill_split4 >= 100000:
		passed += 1
	else:
		failed += 1
	# Reset
	board[7][5] = EMPTY
	board[7][6] = EMPTY
	board[7][7] = EMPTY
	board[7][9] = EMPTY

	# Test 3: Playing to create split-three (XX + X with gap)
	# Place BLACK at (7,5), (7,6). Now play at (7,8) — creates XX_X split-three
	board[7][5] = BLACK
	board[7][6] = BLACK
	var score_create_split3 = evaluator._evaluate_position(board, 7, 8, BLACK)
	print("Test 3 — create split-three: score=%f (expect >=100 half_three via gap)" % score_create_split3)
	if score_create_split3 >= 100:
		passed += 1
	else:
		failed += 1
	# Reset
	board[7][5] = EMPTY
	board[7][6] = EMPTY

	# Test 4: Existing stone board eval with split-three
	board[7][5] = BLACK
	board[7][6] = BLACK
	board[7][8] = BLACK  # XX_X pattern on the board
	var eval_split3 = evaluator.evaluate_board(board, BLACK)
	print("Test 4 — board eval with existing split-three: score=%f" % eval_split3)
	if eval_split3 >= 10.0:
		passed += 1
	else:
		failed += 1
	# Reset
	board[7][5] = EMPTY
	board[7][6] = EMPTY
	board[7][8] = EMPTY

	# Test 5: Consecutive still works — plain open-three XXX
	board[7][6] = BLACK
	board[7][7] = BLACK
	board[7][8] = BLACK
	var eval_open3 = evaluator.evaluate_board(board, BLACK)
	print("Test 5 — existing open-three: score=%f (expect ~100 = 1000*0.1)" % eval_open3)
	if eval_open3 >= 50.0:
		passed += 1
	else:
		failed += 1

	print("")
	print("Results: %d passed, %d failed" % [passed, failed])
	if failed == 0:
		print("OK")
	else:
		print("FAIL")
	quit()
