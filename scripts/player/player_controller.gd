extends RefCounted

signal move_decided(row: int, col: int)

enum Type { LOCAL_HUMAN, REMOTE_NETWORK, LOCAL_AI }

var player_type: Type
var color: int  # GameLogic.BLACK or GameLogic.WHITE


func request_move(_board: Array, _current_player: int, _move_history: Array) -> void:
	# Subclasses override. When ready, emit move_decided(row, col).
	pass


func cancel() -> void:
	# Called when game resets or ends while waiting for a move.
	pass
