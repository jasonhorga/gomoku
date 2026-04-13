extends SceneTree

# Phase 1 unit tests: Player abstraction + GameManager refactor

const _GameLogic = preload("res://scripts/game_logic.gd")
const _PlayerController = preload("res://scripts/player/player_controller.gd")

var tests_passed: int = 0
var tests_failed: int = 0


func _init() -> void:
	print("=== Phase 1 Unit Tests ===\n")

	test_game_logic_basics()
	test_player_controller_types()
	test_human_player()
	test_local_pvp_flow()
	test_full_game_win()

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


func assert_false(val: bool, msg: String) -> void:
	assert_eq(val, false, msg)


func test_game_logic_basics() -> void:
	print("[GameLogic]")
	var logic = _GameLogic.new()

	assert_eq(logic.board.size(), 15, "board has 15 rows")
	assert_eq(logic.current_player, _GameLogic.BLACK, "black goes first")
	assert_false(logic.game_over, "game not over at start")

	# Place a stone
	var ok := logic.place_stone(7, 7)
	assert_true(ok, "place stone at center")
	assert_eq(logic.board[7][7], _GameLogic.BLACK, "center is black")
	assert_eq(logic.current_player, _GameLogic.WHITE, "white's turn after black")
	assert_eq(logic.move_history.size(), 1, "1 move in history")

	# Can't place on occupied cell
	ok = logic.place_stone(7, 7)
	assert_false(ok, "can't place on occupied cell")

	# Win detection: 5 in a row
	logic.reset()
	for i in range(5):
		logic.place_stone(0, i)  # black at row 0
		if i < 4:
			logic.place_stone(1, i)  # white at row 1
	assert_true(logic.game_over, "game over after 5 in a row")
	assert_eq(logic.winner, _GameLogic.BLACK, "black wins")


func test_player_controller_types() -> void:
	print("[PlayerController]")
	var human = load("res://scripts/player/human_player.gd").new()
	assert_eq(human.player_type, _PlayerController.Type.LOCAL_HUMAN, "human type is LOCAL_HUMAN")
	# network_player requires NetworkManager autoload, skip in standalone test
	print("  SKIP: network_player (requires autoload)")


func test_human_player() -> void:
	print("[HumanPlayer]")
	var human = load("res://scripts/player/human_player.gd").new()
	human.color = _GameLogic.BLACK

	# Use array to capture signal result (ints are value types in lambdas)
	var result: Array = []
	human.move_decided.connect(func(r, c):
		result.append(Vector2i(r, c))
	)

	human.submit_move(3, 4)
	assert_eq(result.size(), 1, "move_decided signal emitted")
	assert_eq(result[0], Vector2i(3, 4), "move_decided has correct coords")


func test_local_pvp_flow() -> void:
	print("[Local PvP Flow]")
	# Simulate a local PvP game using the player abstraction
	var logic = _GameLogic.new()
	var p_black = load("res://scripts/player/human_player.gd").new()
	p_black.color = _GameLogic.BLACK
	var p_white = load("res://scripts/player/human_player.gd").new()
	p_white.color = _GameLogic.WHITE

	# Track moves via signals
	var moves_received: Array = []

	p_black.move_decided.connect(func(r, c):
		moves_received.append(Vector2i(r, c))
	, CONNECT_ONE_SHOT)

	# Black submits a move
	p_black.submit_move(7, 7)
	assert_eq(moves_received.size(), 1, "black move received")
	assert_eq(moves_received[0], Vector2i(7, 7), "black move is (7,7)")

	# Apply to logic
	var ok := logic.place_stone(moves_received[0].x, moves_received[0].y)
	assert_true(ok, "black move applied to logic")
	assert_eq(logic.current_player, _GameLogic.WHITE, "now white's turn")

	# White submits
	moves_received.clear()
	p_white.move_decided.connect(func(r, c):
		moves_received.append(Vector2i(r, c))
	, CONNECT_ONE_SHOT)
	p_white.submit_move(8, 8)
	assert_eq(moves_received.size(), 1, "white move received")

	ok = logic.place_stone(moves_received[0].x, moves_received[0].y)
	assert_true(ok, "white move applied to logic")
	assert_eq(logic.current_player, _GameLogic.BLACK, "back to black's turn")


func test_full_game_win() -> void:
	print("[Full Game Win via Players]")
	var logic = _GameLogic.new()
	# Simulate: black wins with horizontal 5 at row 3
	# Black: (3,0) (3,1) (3,2) (3,3) (3,4)
	# White: (4,0) (4,1) (4,2) (4,3)
	var black_moves = [Vector2i(3,0), Vector2i(3,1), Vector2i(3,2), Vector2i(3,3), Vector2i(3,4)]
	var white_moves = [Vector2i(4,0), Vector2i(4,1), Vector2i(4,2), Vector2i(4,3)]

	for i in range(5):
		logic.place_stone(black_moves[i].x, black_moves[i].y)
		if i < 4:
			logic.place_stone(white_moves[i].x, white_moves[i].y)

	assert_true(logic.game_over, "game over after 5 in a row")
	assert_eq(logic.winner, _GameLogic.BLACK, "black wins horizontal")
