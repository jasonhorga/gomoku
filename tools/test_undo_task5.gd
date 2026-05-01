extends Node

const GameLogic = preload("res://scripts/game_logic.gd")
const PlayerController = preload("res://scripts/player/player_controller.gd")
const HumanPlayer = preload("res://scripts/player/human_player.gd")

class InstantAI:
	extends PlayerController
	var ai_engine = null
	var move: Vector2i

	func _init(p_move: Vector2i) -> void:
		player_type = Type.LOCAL_AI
		move = p_move

	func request_move(_board: Array, _current_player: int, _move_history: Array) -> void:
		move_decided.emit(move.x, move.y)

	func cancel() -> void:
		pass

class PendingAI:
	extends PlayerController
	var ai_engine = null
	var cancel_count: int = 0
	var request_count: int = 0

	func _init() -> void:
		player_type = Type.LOCAL_AI

	func request_move(_board: Array, _current_player: int, _move_history: Array) -> void:
		request_count += 1

	func cancel() -> void:
		cancel_count += 1

var failures: Array[String] = []

func _ready() -> void:
	_run_tests()
	if failures.is_empty():
		print("UNDO_TASK5_TESTS PASS")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)

func _run_tests() -> void:
	_test_local_pvp_undo_free()
	_test_local_pvp_undo_renju()
	_test_local_pvp_undo_to_empty_disables_capability()
	_test_vs_ai_undo_after_ai_responded_removes_pair()
	_test_vs_ai_undo_while_ai_thinking_removes_pending_human_move()
	_test_human_white_opening_undo_disabled()
	_test_undo_replay_failure_preserves_active_request()
	_test_invalid_history_replay_does_not_mutate_state()

func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _assert_false(condition: bool, message: String) -> void:
	if condition:
		failures.append(message)

func _assert_eq(actual, expected, message: String) -> void:
	if actual != expected:
		failures.append("%s expected=%s actual=%s" % [message, str(expected), str(actual)])

func _new_manager():
	var manager = get_node("/root/GameManager")
	manager._move_requests_paused = false
	manager._move_request_epoch = 0
	manager.ai_move_delay = 0.5
	manager._invalid_retries = 0
	return manager

func _human(color: int):
	var human = HumanPlayer.new()
	human.color = color
	return human

func _move_list(history: Array[Vector2i]) -> Array[String]:
	var out: Array[String] = []
	for move in history:
		out.append("%d,%d" % [move.x, move.y])
	return out

func _test_local_pvp_undo_free() -> void:
	var gm = _new_manager()
	gm.setup_local_pvp(false)
	gm.start_game()
	gm.submit_human_move(7, 7)
	gm.submit_human_move(7, 8)
	_assert_true(gm.can_undo_last_turn(), "local PvP free should expose undo capability after moves")
	var ok: bool = gm.undo_last_turn()
	_assert_true(ok, "local PvP free undo should succeed")
	_assert_eq(_move_list(gm.logic.move_history), ["7,7"], "local PvP free should remove one move")
	_assert_eq(gm.logic.current_player, GameLogic.WHITE, "local PvP free should leave white to move")
	_assert_eq(gm.logic.board[7][8], GameLogic.EMPTY, "local PvP free should clear undone stone")
	_assert_eq(gm.logic.board[7][7], GameLogic.BLACK, "local PvP free should keep earlier stone")

func _test_local_pvp_undo_renju() -> void:
	var gm = _new_manager()
	gm.setup_local_pvp(true)
	gm.start_game()
	gm.submit_human_move(7, 7)
	gm.submit_human_move(7, 8)
	_assert_true(gm.can_undo_last_turn(), "local PvP Renju should expose undo capability after moves")
	var ok: bool = gm.undo_last_turn()
	_assert_true(ok, "local PvP Renju undo should succeed")
	_assert_true(gm.logic.forbidden_enabled, "local PvP Renju should preserve forbidden flag")
	_assert_eq(_move_list(gm.logic.move_history), ["7,7"], "local PvP Renju should remove one move")
	_assert_eq(gm.logic.current_player, GameLogic.WHITE, "local PvP Renju should leave white to move")

func _test_local_pvp_undo_to_empty_disables_capability() -> void:
	var gm = _new_manager()
	gm.setup_local_pvp(false)
	gm.start_game()
	gm.submit_human_move(7, 7)
	_assert_true(gm.can_undo_last_turn(), "local PvP should expose undo capability after one move")
	var ok: bool = gm.undo_last_turn()
	_assert_true(ok, "local PvP one-move undo should succeed")
	_assert_eq(gm.logic.move_history.size(), 0, "local PvP one-move undo should empty history")
	_assert_false(gm.can_undo_last_turn(), "local PvP should not expose undo capability after undo empties history")

func _test_vs_ai_undo_after_ai_responded_removes_pair() -> void:
	var gm = _new_manager()
	gm.mode = gm.GameMode.VS_AI
	gm.my_color = GameLogic.BLACK
	gm.forbidden_enabled = false
	gm.logic.forbidden_enabled = false
	gm.players[0] = _human(GameLogic.BLACK)
	var ai = InstantAI.new(Vector2i(7, 8))
	ai.color = GameLogic.WHITE
	gm.players[1] = ai
	gm.start_game()
	gm.submit_human_move(7, 7)
	_assert_eq(_move_list(gm.logic.move_history), ["7,7", "7,8"], "VS AI setup should include human and AI moves")
	_assert_true(gm.can_undo_last_turn(), "VS AI should expose undo capability after AI response")
	var ok: bool = gm.undo_last_turn()
	_assert_true(ok, "VS AI undo after AI response should succeed")
	_assert_eq(gm.logic.move_history.size(), 0, "VS AI after response should remove human+AI pair")
	_assert_false(gm.can_undo_last_turn(), "VS AI should not expose undo capability after undo empties history")
	_assert_eq(gm.logic.current_player, GameLogic.BLACK, "VS AI after response should return to human turn")
	_assert_eq(gm.logic.board[7][7], GameLogic.EMPTY, "VS AI after response should clear human stone")
	_assert_eq(gm.logic.board[7][8], GameLogic.EMPTY, "VS AI after response should clear AI stone")

func _test_vs_ai_undo_while_ai_thinking_removes_pending_human_move() -> void:
	var gm = _new_manager()
	gm.mode = gm.GameMode.VS_AI
	gm.my_color = GameLogic.BLACK
	gm.forbidden_enabled = false
	gm.logic.forbidden_enabled = false
	gm.players[0] = _human(GameLogic.BLACK)
	var ai = PendingAI.new()
	ai.color = GameLogic.WHITE
	gm.players[1] = ai
	gm.start_game()
	gm.submit_human_move(7, 7)
	_assert_eq(_move_list(gm.logic.move_history), ["7,7"], "VS AI thinking setup should only have pending human move")
	_assert_eq(gm.logic.current_player, GameLogic.WHITE, "VS AI thinking setup should be AI turn")
	_assert_true(gm.can_undo_last_turn(), "VS AI should expose undo capability while AI is thinking after human move")
	var ok: bool = gm.undo_last_turn()
	_assert_true(ok, "VS AI undo while AI thinking should succeed")
	_assert_eq(gm.logic.move_history.size(), 0, "VS AI thinking should remove only pending human move")
	_assert_false(gm.can_undo_last_turn(), "VS AI should not expose undo capability after undoing pending human move")
	_assert_eq(gm.logic.current_player, GameLogic.BLACK, "VS AI thinking should return to human turn")
	_assert_true(ai.cancel_count >= 1, "VS AI thinking undo should cancel AI request")

func _test_human_white_opening_undo_disabled() -> void:
	var gm = _new_manager()
	gm.mode = gm.GameMode.VS_AI
	gm.my_color = GameLogic.WHITE
	gm.forbidden_enabled = false
	gm.logic.forbidden_enabled = false
	var ai = InstantAI.new(Vector2i(7, 7))
	ai.color = GameLogic.BLACK
	gm.players[0] = ai
	gm.players[1] = _human(GameLogic.WHITE)
	gm.start_game()
	_assert_eq(_move_list(gm.logic.move_history), ["7,7"], "human-white setup should contain only AI opening")
	_assert_eq(gm.logic.current_player, GameLogic.WHITE, "human-white setup should be human turn")
	_assert_false(gm.can_undo_last_turn(), "human-white opening should not expose undo capability before human move")
	var game_scene = load("res://scenes/game/game.gd").new()
	var undo_button = Button.new()
	game_scene.undo_button = undo_button
	game_scene._update_undo_enabled()
	_assert_true(undo_button.disabled, "UI undo helper should disable in human-white opening state")
	game_scene.free()
	undo_button.free()
	var ok: bool = gm.undo_last_turn()
	_assert_true(not ok, "human-white opening undo should be disabled before human move")
	_assert_eq(_move_list(gm.logic.move_history), ["7,7"], "human-white disabled undo should keep AI opening")
	_assert_eq(gm.logic.board[7][7], GameLogic.BLACK, "human-white disabled undo should not clear AI opening")

func _test_undo_replay_failure_preserves_active_request() -> void:
	var gm = _new_manager()
	gm.mode = gm.GameMode.VS_AI
	gm.my_color = GameLogic.BLACK
	gm.forbidden_enabled = false
	gm.logic.forbidden_enabled = false
	gm.players[0] = _human(GameLogic.BLACK)
	var ai = PendingAI.new()
	ai.color = GameLogic.WHITE
	gm.players[1] = ai
	gm.start_game()
	gm.submit_human_move(7, 7)
	gm._on_move_decided(7, 8)
	gm.submit_human_move(8, 7)
	_assert_eq(_move_list(gm.logic.move_history), ["7,7", "7,8", "8,7"], "replay failure setup should have completed pair plus pending human move")
	_assert_eq(gm.logic.current_player, GameLogic.WHITE, "replay failure setup should be AI turn")
	_assert_eq(ai.request_count, 2, "replay failure setup should have active second AI request")
	_assert_true(ai.move_decided.is_connected(gm._on_move_decided), "replay failure setup should have active move signal")
	gm.logic.move_history[0] = Vector2i(99, 99)
	var ok: bool = gm.undo_last_turn()
	_assert_true(not ok, "undo should fail when replay validation fails")
	_assert_eq(ai.cancel_count, 0, "failed undo should not cancel active AI request")
	_assert_true(ai.move_decided.is_connected(gm._on_move_decided), "failed undo should keep active move signal connected")
	_assert_eq(gm.logic.current_player, GameLogic.WHITE, "failed undo should keep current player")

func _test_invalid_history_replay_does_not_mutate_state() -> void:
	var logic = GameLogic.new()
	logic.place_stone(7, 7)
	logic.place_stone(7, 8)
	var before_history: Array[String] = _move_list(logic.move_history)
	var before_current: int = logic.current_player
	var before_first: int = logic.board[7][7]
	var before_second: int = logic.board[7][8]
	var invalid: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, 1)]
	var ok: bool = logic.rebuild_from_history(invalid)
	_assert_true(not ok, "invalid history rebuild should fail")
	_assert_eq(_move_list(logic.move_history), before_history, "invalid history rebuild should restore history")
	_assert_eq(logic.current_player, before_current, "invalid history rebuild should restore current player")
	_assert_eq(logic.board[7][7], before_first, "invalid history rebuild should restore first stone")
	_assert_eq(logic.board[7][8], before_second, "invalid history rebuild should restore second stone")
	_assert_eq(logic.board[1][1], GameLogic.EMPTY, "invalid history rebuild should not leave partial replay stone")
