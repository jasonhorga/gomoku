extends "res://scripts/player/player_controller.gd"

# Connects to Python AI server via TCP for Level 6 (neural network AI).

var _client = null  # AIServiceClient
var _thread: Thread = null
var _cancelled: bool = false


func _init() -> void:
	player_type = Type.REMOTE_AI
	_client = load("res://scripts/net/ai_service_client.gd").new()


func is_server_available() -> bool:
	if _client.is_connected_to_server():
		return true
	return _client.connect_to_server()


func request_move(board: Array, current_player: int, move_history: Array) -> void:
	_cancelled = false
	# Deep copy board
	var board_copy: Array = []
	for row in board:
		board_copy.append(row.duplicate())

	# Extract last move for v2 CNN's last-move plane
	var last_move = null
	if move_history.size() > 0:
		var last = move_history[move_history.size() - 1]
		if last is Vector2i:
			last_move = [last.x, last.y]
		elif last is Array and last.size() >= 2:
			last_move = [int(last[0]), int(last[1])]

	_thread = Thread.new()
	_thread.start(_compute_move.bind(board_copy, current_player, last_move))


func _compute_move(board: Array, current_player: int, last_move = null) -> void:
	if not _client.is_connected_to_server():
		if not _client.connect_to_server():
			if not _cancelled:
				# Fallback: play center or first available
				_emit_move.call_deferred(7, 7)
			return

	# Convert 2D array to format matching Python
	var board_flat: Array = []
	for row in board:
		var r: Array = []
		for cell in row:
			r.append(int(cell))
		board_flat.append(r)

	var response = _client.request_move(board_flat, current_player, last_move)
	if _cancelled:
		return

	if response.is_empty():
		_emit_move.call_deferred(7, 7)
	else:
		_emit_move.call_deferred(int(response.get("row", 7)), int(response.get("col", 7)))


func _emit_move(row: int, col: int) -> void:
	move_decided.emit(row, col)


func cancel() -> void:
	_cancelled = true
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null


func disconnect_server() -> void:
	if _client != null:
		_client.disconnect_from_server()
