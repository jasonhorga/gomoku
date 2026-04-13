extends RefCounted

# Analyzes game records and tunes PatternEvaluator weights
# based on win/loss correlation of pattern types.

const BOARD_SIZE: int = 15
const EMPTY: int = 0
const BLACK: int = 1
const WHITE: int = 2

var learning_rate: float = 0.02
var evaluator_script = preload("res://scripts/ai/pattern_evaluator.gd")


func tune_from_records(records: Array, base_weights: Dictionary) -> Dictionary:
	# Analyze each game: replay moves, at each position evaluate which
	# pattern weights were active, correlate with final outcome.
	var adjustments: Dictionary = {}
	for key in base_weights:
		adjustments[key] = 0.0

	var analyzed: int = 0

	for record in records:
		if record.result == EMPTY:
			continue  # skip draws

		var board: Array = _make_board()
		var winner: int = record.result
		var current: int = BLACK

		for move_data in record.moves:
			var row: int = move_data[0]
			var col: int = move_data[1]
			if row < 0 or row >= BOARD_SIZE or col < 0 or col >= BOARD_SIZE:
				break
			if board[row][col] != EMPTY:
				break

			# Before placing: evaluate what patterns this move creates
			var eval = evaluator_script.new()
			eval.weights = base_weights.duplicate()
			var pattern_activations: Dictionary = _get_pattern_activations(eval, board, row, col, current)

			# If this player won, increase weights for their patterns
			# If they lost, decrease
			var sign: float = 1.0 if current == winner else -1.0
			for key in pattern_activations:
				if key in adjustments:
					adjustments[key] += sign * pattern_activations[key]

			board[row][col] = current
			current = WHITE if current == BLACK else BLACK

		analyzed += 1

	if analyzed == 0:
		return base_weights

	# Normalize adjustments and apply
	var new_weights: Dictionary = base_weights.duplicate()
	for key in new_weights:
		if adjustments[key] != 0:
			var norm: float = adjustments[key] / analyzed
			new_weights[key] *= (1.0 + norm * learning_rate)
			new_weights[key] = maxf(1.0, new_weights[key])  # floor at 1

	return new_weights


func _get_pattern_activations(eval, board: Array, row: int, col: int, player: int) -> Dictionary:
	# Returns a dict of pattern_type → activation_count
	var activations: Dictionary = {}
	var directions = [Vector2i(0,1), Vector2i(1,0), Vector2i(1,1), Vector2i(1,-1)]

	for dir in directions:
		var count: int = 1
		var open_ends: int = 0

		var pos = eval._count_consecutive(board, row, col, dir.x, dir.y, player)
		count += pos.x
		if pos.y:
			open_ends += 1

		var neg = eval._count_consecutive(board, row, col, -dir.x, -dir.y, player)
		count += neg.x
		if neg.y:
			open_ends += 1

		var pattern_name: String = _classify_pattern(count, open_ends)
		if pattern_name != "":
			activations[pattern_name] = activations.get(pattern_name, 0.0) + 1.0

	return activations


func _classify_pattern(count: int, open_ends: int) -> String:
	if count >= 5:
		return "five"
	if open_ends == 0:
		return ""
	match count:
		4:
			return "open_four" if open_ends == 2 else "half_four"
		3:
			return "open_three" if open_ends == 2 else "half_three"
		2:
			return "open_two" if open_ends == 2 else "half_two"
	return ""


func _make_board() -> Array:
	var board: Array = []
	for r in range(BOARD_SIZE):
		var row: Array = []
		row.resize(BOARD_SIZE)
		row.fill(EMPTY)
		board.append(row)
	return board
