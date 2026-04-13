extends "res://scripts/ai/ai_engine.gd"

# Level 6 AI: Neural network via Python server.
# If server unavailable, falls back to Level 5 MCTS.

var _tcp_client = null
var _use_server: bool = false
var _fallback_mcts = null


func _init() -> void:
	_tcp_client = load("res://scripts/net/ai_service_client.gd").new()
	if _tcp_client.connect_to_server():
		_use_server = true
	else:
		# Fallback: MCTS (same as Level 5)
		_fallback_mcts = load("res://scripts/ai/ai_mcts.gd").new(3000)


func choose_move(board: Array, current_player: int, move_history: Array) -> Vector2i:
	# Try server first
	if _use_server and _tcp_client.is_connected_to_server():
		var board_flat: Array = []
		for row in board:
			var r: Array = []
			for cell in row:
				r.append(int(cell))
			board_flat.append(r)
		var response = _tcp_client.request_move(board_flat, current_player)
		if not response.is_empty():
			return Vector2i(int(response.get("row", 7)), int(response.get("col", 7)))
		# Server failed — switch to fallback
		_use_server = false
		_fallback_mcts = load("res://scripts/ai/ai_mcts.gd").new(3000)

	# Fallback: MCTS
	return _fallback_mcts.choose_move(board, current_player, move_history)


func get_name() -> String:
	if _use_server:
		return "Neural(server)"
	return "Neural(MCTS fallback)"
