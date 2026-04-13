extends RefCounted

# Pattern evaluator: scores board positions by recognizing gomoku patterns
# in all 4 directions. Used by Heuristic AI and Minimax evaluation.

const BOARD_SIZE: int = 15
const EMPTY: int = 0
const BLACK: int = 1
const WHITE: int = 2

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(0, 1),   # horizontal
	Vector2i(1, 0),   # vertical
	Vector2i(1, 1),   # diagonal ↘
	Vector2i(1, -1),  # diagonal ↙
]

# Tunable weights
var weights: Dictionary = {
	"five": 100000,
	"open_four": 10000,
	"half_four": 1000,
	"open_three": 1000,
	"half_three": 100,
	"open_two": 100,
	"half_two": 10,
}

# Defense multiplier (slightly prefer blocking over building)
var defense_weight: float = 1.1


func _init() -> void:
	# Try to load tuned weights if available
	load_weights("user://ai_weights/pattern_weights.json")


func score_cell(board: Array, row: int, col: int, player: int) -> float:
	# Score a single empty cell for 'player' placing a stone there.
	# Considers both offense (own patterns) and defense (opponent patterns).
	if board[row][col] != EMPTY:
		return 0.0

	var opponent: int = BLACK if player == WHITE else WHITE

	# Temporarily place stone to evaluate
	var attack_score: float = _evaluate_position(board, row, col, player)
	var defend_score: float = _evaluate_position(board, row, col, opponent)

	return attack_score + defend_score * defense_weight


func evaluate_board(board: Array, player: int) -> float:
	# Full board evaluation: sum of all patterns for both sides.
	# Positive = good for 'player', negative = good for opponent.
	var opponent: int = BLACK if player == WHITE else WHITE
	var score: float = 0.0

	for row in range(BOARD_SIZE):
		for col in range(BOARD_SIZE):
			if board[row][col] == player:
				score += _evaluate_existing_stone(board, row, col, player)
			elif board[row][col] == opponent:
				score -= _evaluate_existing_stone(board, row, col, opponent)

	return score


func _evaluate_position(board: Array, row: int, col: int, player: int) -> float:
	# Evaluate what patterns would be created by placing 'player' at (row, col)
	var total: float = 0.0

	for dir in DIRECTIONS:
		var count: int = 1  # the stone we're placing
		var open_ends: int = 0

		# Count in positive direction
		var pos_count := _count_consecutive(board, row, col, dir.x, dir.y, player)
		count += pos_count.x  # consecutive stones
		if pos_count.y:       # is end open?
			open_ends += 1

		# Count in negative direction
		var neg_count := _count_consecutive(board, row, col, -dir.x, -dir.y, player)
		count += neg_count.x
		if neg_count.y:
			open_ends += 1

		total += _pattern_score(count, open_ends)

	return total


func _evaluate_existing_stone(board: Array, row: int, col: int, player: int) -> float:
	# Evaluate patterns around an existing stone (for board evaluation)
	var total: float = 0.0

	for dir in DIRECTIONS:
		# Only count in one direction to avoid double-counting
		var count: int = 1
		var open_ends: int = 0

		var pos_count := _count_consecutive(board, row, col, dir.x, dir.y, player)
		count += pos_count.x
		if pos_count.y:
			open_ends += 1

		var neg_count := _count_consecutive(board, row, col, -dir.x, -dir.y, player)
		count += neg_count.x
		if neg_count.y:
			open_ends += 1

		# Only score if this is the leftmost/topmost stone to avoid double counting
		var prev_r: int = row - dir.x
		var prev_c: int = col - dir.y
		if prev_r >= 0 and prev_r < BOARD_SIZE and prev_c >= 0 and prev_c < BOARD_SIZE:
			if board[prev_r][prev_c] == player:
				continue  # not the start of this line

		total += _pattern_score(count, open_ends) * 0.1  # scale down for board eval

	return total


func _count_consecutive(board: Array, row: int, col: int, dr: int, dc: int, player: int) -> Vector2i:
	# Returns Vector2i(consecutive_count, is_open_end)
	var count: int = 0
	var r: int = row + dr
	var c: int = col + dc

	while r >= 0 and r < BOARD_SIZE and c >= 0 and c < BOARD_SIZE:
		if board[r][c] == player:
			count += 1
			r += dr
			c += dc
		else:
			break

	# Check if the end is open (empty) or blocked
	var is_open: int = 0
	if r >= 0 and r < BOARD_SIZE and c >= 0 and c < BOARD_SIZE:
		if board[r][c] == EMPTY:
			is_open = 1

	return Vector2i(count, is_open)


func _pattern_score(count: int, open_ends: int) -> float:
	if count >= 5:
		return weights["five"]
	if open_ends == 0:
		return 0.0  # completely blocked, worthless

	match count:
		4:
			if open_ends == 2:
				return weights["open_four"]
			else:
				return weights["half_four"]
		3:
			if open_ends == 2:
				return weights["open_three"]
			else:
				return weights["half_three"]
		2:
			if open_ends == 2:
				return weights["open_two"]
			else:
				return weights["half_two"]
		1:
			return 1.0  # single stone with one open end
		_:
			return 0.0


func load_weights(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return false
	var data = json.data
	if data is Dictionary:
		for key in data:
			if key in weights:
				weights[key] = float(data[key])
		return true
	return false


func save_weights(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(weights, "\t"))
	return true
