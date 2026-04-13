extends "res://scripts/ai/ai_engine.gd"


func choose_move(board: Array, current_player: int, move_history: Array) -> Vector2i:
	var candidates := get_nearby_empty_cells(board, 2)
	if candidates.is_empty():
		return Vector2i(-1, -1)
	return candidates[randi() % candidates.size()]


func get_name() -> String:
	return "Random"
