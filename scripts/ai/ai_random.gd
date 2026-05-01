extends "res://scripts/ai/ai_engine.gd"


func choose_move(board: Array, current_player: int, move_history: Array) -> Vector2i:
	var candidates := filter_legal_candidates(board, current_player, get_nearby_empty_cells(board, 2))
	if candidates.is_empty():
		return get_any_legal_empty_cell(board, current_player)
	return candidates[randi() % candidates.size()]


func get_name() -> String:
	return "Random"
