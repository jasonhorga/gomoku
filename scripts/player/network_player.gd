extends "res://scripts/player/player_controller.gd"


func _init() -> void:
	player_type = Type.REMOTE_NETWORK


func request_move(_board: Array, _current_player: int, _move_history: Array) -> void:
	# Moves arrive via NetworkManager.move_received signal.
	if not NetworkManager.move_received.is_connected(_on_network_move):
		NetworkManager.move_received.connect(_on_network_move)


func _on_network_move(row: int, col: int) -> void:
	move_decided.emit(row, col)


func cancel() -> void:
	if NetworkManager.move_received.is_connected(_on_network_move):
		NetworkManager.move_received.disconnect(_on_network_move)
