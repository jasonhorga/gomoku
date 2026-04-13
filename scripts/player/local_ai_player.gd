extends "res://scripts/player/player_controller.gd"

var ai_engine  # AIEngine instance
var _thread: Thread = null
var _cancelled: bool = false


func _init(engine = null) -> void:
	player_type = Type.LOCAL_AI
	ai_engine = engine


func request_move(board: Array, current_player: int, move_history: Array) -> void:
	_cancelled = false
	# Deep copy the board so AI search doesn't affect display state
	var board_copy: Array = []
	for row in board:
		board_copy.append(row.duplicate())

	_thread = Thread.new()
	_thread.start(_compute_move.bind(board_copy, current_player, move_history.duplicate()))


func _compute_move(board: Array, current_player: int, move_history: Array) -> void:
	var move: Vector2i = ai_engine.choose_move(board, current_player, move_history)
	if not _cancelled:
		_emit_move.call_deferred(move.x, move.y)


func _emit_move(row: int, col: int) -> void:
	move_decided.emit(row, col)


func cancel() -> void:
	_cancelled = true
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
