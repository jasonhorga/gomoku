extends "res://scripts/player/player_controller.gd"


func _init() -> void:
	player_type = Type.LOCAL_HUMAN


func request_move(_board: Array, _current_player: int, _move_history: Array) -> void:
	# Human moves arrive via submit_move() called by board.gd on click.
	pass


func submit_move(row: int, col: int) -> void:
	move_decided.emit(row, col)
