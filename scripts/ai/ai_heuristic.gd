extends "res://scripts/ai/ai_engine.gd"

var evaluator = preload("res://scripts/ai/pattern_evaluator.gd").new()


func choose_move(board: Array, current_player: int, move_history: Array) -> Vector2i:
	var candidates := get_nearby_empty_cells(board, 2)
	if candidates.is_empty():
		return Vector2i(-1, -1)

	var best_move: Vector2i = candidates[0]
	var best_score: float = -1.0

	for pos in candidates:
		var score: float = evaluator.score_cell(board, pos.x, pos.y, current_player)
		if score > best_score:
			best_score = score
			best_move = pos

	return best_move


func get_name() -> String:
	return "Heuristic"
