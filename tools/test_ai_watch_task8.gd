extends Node

const GameLogic = preload("res://scripts/game_logic.gd")
const PlayerController = preload("res://scripts/player/player_controller.gd")

class PendingAI:
	extends PlayerController
	var ai_engine = null
	var request_count: int = 0
	var cancel_count: int = 0

	func _init() -> void:
		player_type = Type.LOCAL_AI

	func request_move(_board: Array, _current_player: int, _move_history: Array) -> void:
		request_count += 1

	func cancel() -> void:
		cancel_count += 1

var failures: Array[String] = []
var _state_changes: int = 0


func _ready() -> void:
	await _run_tests()
	if failures.is_empty():
		print("AI_WATCH_TASK8_TESTS PASS")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)


func _run_tests() -> void:
	_test_pause_blocks_ai_vs_ai_requests()
	_test_step_advances_exactly_one_move()
	await _test_paused_step_retries_invalid_move_until_one_accepted()
	await _test_pause_during_in_progress_invalid_move_still_resolves_current_move()
	_test_auto_resume_requests_current_move()
	_test_game_scene_exposes_ai_watch_controls()


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
	var gm = get_node("/root/GameManager")
	gm._cancel_current_move()
	gm._move_requests_paused = false
	gm._move_request_epoch = 0
	gm.ai_move_delay = 0.0
	gm._invalid_retries = 0
	_state_changes = 0
	if gm.has_signal("ai_watch_state_changed") and not gm.ai_watch_state_changed.is_connected(_on_ai_watch_state_changed):
		gm.ai_watch_state_changed.connect(_on_ai_watch_state_changed)
	return gm


func _on_ai_watch_state_changed() -> void:
	_state_changes += 1


func _setup_watch_game(paused: bool):
	var gm = _new_manager()
	var black = PendingAI.new()
	black.color = GameLogic.BLACK
	var white = PendingAI.new()
	white.color = GameLogic.WHITE
	gm.mode = gm.GameMode.AI_VS_AI
	gm.my_color = -1
	gm.forbidden_enabled = false
	gm.logic.forbidden_enabled = false
	gm.players[0] = black
	gm.players[1] = white
	gm.ai_watch_paused = false
	gm.ai_step_requested = false
	gm.ai_move_in_progress = false
	gm.ai_move_delay = 0.0
	if paused:
		gm.set_ai_watch_paused(true)
	gm.start_game()
	return {"gm": gm, "black": black, "white": white}


func _test_pause_blocks_ai_vs_ai_requests() -> void:
	var fixture = _setup_watch_game(true)
	var gm = fixture.gm
	var black = fixture.black
	var white = fixture.white
	_assert_true(gm.ai_watch_paused, "AI watch pause flag should stay true after starting paused watch game")
	_assert_false(gm.ai_step_requested, "paused start should not leave a step request pending")
	_assert_false(gm.ai_move_in_progress, "paused watch game should not mark move in progress before request")
	_assert_eq(black.request_count, 0, "paused watch game should not request black move")
	_assert_eq(white.request_count, 0, "paused watch game should not request white move")
	_assert_eq(gm.logic.move_history.size(), 0, "paused watch game should not place moves")
	_assert_true(_state_changes > 0, "paused gate should notify AI watch state listeners")


func _test_step_advances_exactly_one_move() -> void:
	var fixture = _setup_watch_game(true)
	var gm = fixture.gm
	var black = fixture.black
	var white = fixture.white
	_state_changes = 0
	gm.request_ai_watch_step()
	_assert_true(gm.ai_move_in_progress, "step should request the current black move")
	_assert_eq(white.request_count, 0, "step should not request white before black responds")
	_assert_false(gm.ai_step_requested, "step request should clear when an AI move request starts")
	_assert_true(gm.ai_move_in_progress, "step should mark AI move in progress while waiting for decision")
	gm._on_move_decided(7, 7)
	_assert_eq(gm.logic.move_history.size(), 1, "step should place exactly one move after AI responds")
	_assert_eq(gm.logic.move_history[0], Vector2i(7, 7), "step should place black's chosen move")
	_assert_eq(white.request_count, 0, "paused step should not automatically request the next white move")
	_assert_true(gm.ai_watch_paused, "watch should remain paused after one step")
	_assert_false(gm.ai_move_in_progress, "move-in-progress should clear after accepted step move")
	_assert_true(_state_changes >= 2, "step start and finish should notify AI watch state listeners")


func _test_paused_step_retries_invalid_move_until_one_accepted() -> void:
	var fixture = _setup_watch_game(true)
	var gm = fixture.gm
	var black = fixture.black
	var white = fixture.white
	gm.request_ai_watch_step()
	_assert_eq(black.request_count, 1, "paused step should request black once")
	black.move_decided.emit(-1, -1)
	_assert_eq(gm.logic.move_history.size(), 0, "invalid step result should not place a stone")
	_assert_true(gm.ai_watch_paused, "watch should remain paused while retrying invalid step result")
	_assert_true(gm.ai_move_in_progress, "invalid step result should keep current move resolving")
	_assert_eq(black.request_count, 1, "invalid step result should wait for one-shot cleanup before retrying")
	_assert_eq(white.request_count, 0, "invalid step retry should not request white")
	await get_tree().process_frame
	_assert_eq(black.request_count, 2, "invalid step result should retry current black move even while paused after cleanup")
	black.move_decided.emit(7, 7)
	_assert_eq(gm.logic.move_history.size(), 1, "invalid-then-valid step should place exactly one stone")
	_assert_eq(gm.logic.move_history[0], Vector2i(7, 7), "invalid-then-valid step should accept black's valid retry")
	_assert_true(gm.ai_watch_paused, "watch should remain paused after invalid-then-valid step")
	_assert_false(gm.ai_move_in_progress, "accepted retry should clear move-in-progress")
	_assert_eq(black.request_count, 2, "accepted retry should not duplicate black requests")
	_assert_eq(white.request_count, 0, "accepted paused step should not request next white move")


func _test_pause_during_in_progress_invalid_move_still_resolves_current_move() -> void:
	var fixture = _setup_watch_game(false)
	var gm = fixture.gm
	var black = fixture.black
	var white = fixture.white
	_assert_eq(black.request_count, 1, "auto watch should request initial black move")
	gm.set_ai_watch_paused(true)
	_assert_true(gm.ai_watch_paused, "pause during in-progress move should set pause flag")
	_assert_true(gm.ai_move_in_progress, "pause during in-progress move should not cancel the current request")
	black.move_decided.emit(-1, -1)
	_assert_eq(gm.logic.move_history.size(), 0, "invalid in-progress result should not place a stone")
	_assert_true(gm.ai_move_in_progress, "invalid in-progress result should keep current move resolving despite pause")
	_assert_eq(black.request_count, 1, "invalid in-progress result should wait for one-shot cleanup before retrying")
	_assert_eq(white.request_count, 0, "invalid in-progress retry should not request white")
	await get_tree().process_frame
	_assert_eq(black.request_count, 2, "invalid in-progress result should retry current black move despite pause after cleanup")
	black.move_decided.emit(7, 7)
	_assert_eq(gm.logic.move_history.size(), 1, "valid retry after pause should place exactly one current stone")
	_assert_eq(gm.logic.move_history[0], Vector2i(7, 7), "valid retry after pause should accept current black move")
	_assert_true(gm.ai_watch_paused, "watch should remain paused after resolving in-progress move")
	_assert_false(gm.ai_move_in_progress, "resolved in-progress move should clear move-in-progress")
	_assert_eq(white.request_count, 0, "resolved in-progress move should not request next white move while paused")


func _test_auto_resume_requests_current_move() -> void:
	var fixture = _setup_watch_game(true)
	var gm = fixture.gm
	var black = fixture.black
	var white = fixture.white
	gm.request_ai_watch_step()
	gm._on_move_decided(7, 7)
	_assert_eq(white.request_count, 0, "setup should be paused on white turn after one step")
	gm.set_ai_watch_paused(false)
	_assert_false(gm.ai_watch_paused, "auto resume should clear pause flag")
	_assert_true(gm.ai_move_in_progress, "auto resume should request current white move")
	_assert_true(gm.ai_move_in_progress, "auto resume should mark white move in progress")


func _test_game_scene_exposes_ai_watch_controls() -> void:
	var scene: PackedScene = load("res://scenes/game/game.tscn")
	_assert_true(scene != null, "game scene should load")
	if scene == null:
		return
	var game = scene.instantiate()
	add_child(game)
	var controls = game.get_node_or_null("%AiWatchControls")
	var pause = game.get_node_or_null("%PauseButton")
	var step = game.get_node_or_null("%StepButton")
	var auto = game.get_node_or_null("%AutoButton")
	_assert_true(controls != null, "game scene should expose unique AiWatchControls")
	_assert_true(pause != null, "game scene should expose unique PauseButton")
	_assert_true(step != null, "game scene should expose unique StepButton")
	_assert_true(auto != null, "game scene should expose unique AutoButton")
	if pause != null:
		_assert_eq(pause.text, "暂停", "PauseButton should use Chinese pause label")
		_assert_eq(pause.custom_minimum_size.y, 52.0, "PauseButton should be 52px high")
	if step != null:
		_assert_eq(step.text, "下一步", "StepButton should use Chinese step label")
		_assert_eq(step.custom_minimum_size.y, 52.0, "StepButton should be 52px high")
	if auto != null:
		_assert_eq(auto.text, "自动播放", "AutoButton should use Chinese auto label")
		_assert_eq(auto.custom_minimum_size.y, 52.0, "AutoButton should be 52px high")
	game.queue_free()
	var gm = get_node("/root/GameManager")
	gm._cancel_current_move()
