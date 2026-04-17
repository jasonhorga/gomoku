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
	# Evaluate what patterns would be created by placing 'player' at (row, col).
	# Considers both consecutive AND gapped patterns (split-three, split-four).
	var total: float = 0.0

	for dir in DIRECTIONS:
		var pos := _scan_line(board, row, col, dir.x, dir.y, player)
		var neg := _scan_line(board, row, col, -dir.x, -dir.y, player)

		# Consecutive score
		var con_total: int = 1 + pos.x + neg.x
		var open_ends: int = pos.z + neg.z
		var con_score: float = _pattern_score(con_total, open_ends)

		# Gapped scores (gap on positive or negative side)
		var gap_score: float = 0.0
		if pos.y > 0:
			gap_score = max(gap_score, _gapped_score(1 + pos.x + neg.x + pos.y))
		if neg.y > 0:
			gap_score = max(gap_score, _gapped_score(1 + pos.x + neg.x + neg.y))

		total += max(con_score, gap_score)

	return total


func _evaluate_existing_stone(board: Array, row: int, col: int, player: int) -> float:
	# Evaluate patterns around an existing stone (for board evaluation).
	# Only scores from the "start" of each line to avoid double-counting.
	var total: float = 0.0

	for dir in DIRECTIONS:
		# Skip if there's a same-color stone before us (not the start)
		var prev_r: int = row - dir.x
		var prev_c: int = col - dir.y
		var prev_in_bounds: bool = prev_r >= 0 and prev_r < BOARD_SIZE and prev_c >= 0 and prev_c < BOARD_SIZE
		if prev_in_bounds and board[prev_r][prev_c] == player:
			continue  # not the start of this consecutive line

		# Skip if there's a gapped stone before us (X _ [me]) — part of a gapped line
		if prev_in_bounds and board[prev_r][prev_c] == EMPTY:
			var pp_r: int = row - 2 * dir.x
			var pp_c: int = col - 2 * dir.y
			if pp_r >= 0 and pp_r < BOARD_SIZE and pp_c >= 0 and pp_c < BOARD_SIZE:
				if board[pp_r][pp_c] == player:
					continue  # a gapped line starts before us, don't double-count

		# We're the start. Scan forward for consecutive + gapped pattern.
		var pos := _scan_line(board, row, col, dir.x, dir.y, player)
		var count: int = 1 + pos.x
		var open_ends: int = pos.z
		if prev_in_bounds and board[prev_r][prev_c] == EMPTY:
			open_ends += 1

		var con_score: float = _pattern_score(count, open_ends)

		var gap_score: float = 0.0
		if pos.y > 0:
			gap_score = _gapped_score(1 + pos.x + pos.y)

		total += max(con_score, gap_score) * 0.1  # scale down for board eval

	return total


func _scan_line(board: Array, row: int, col: int, dr: int, dc: int, player: int) -> Vector3i:
	# Scan in one direction, returning (consecutive, gap_stones, end_open):
	#   consecutive: adjacent same-color stones
	#   gap_stones:  same-color stones after one empty gap (0 if none)
	#   end_open:    1 if cell after consecutive is empty, else 0
	var cons: int = 0
	var r: int = row + dr
	var c: int = col + dc

	while r >= 0 and r < BOARD_SIZE and c >= 0 and c < BOARD_SIZE:
		if board[r][c] == player:
			cons += 1
			r += dr
			c += dc
		else:
			break

	var end_open: int = 0
	var gap_stones: int = 0

	if r >= 0 and r < BOARD_SIZE and c >= 0 and c < BOARD_SIZE and board[r][c] == EMPTY:
		end_open = 1
		# Look past the gap for more stones of same color
		var nr: int = r + dr
		var nc: int = c + dc
		while nr >= 0 and nr < BOARD_SIZE and nc >= 0 and nc < BOARD_SIZE:
			if board[nr][nc] == player:
				gap_stones += 1
				nr += dr
				nc += dc
			else:
				break

	return Vector3i(cons, gap_stones, end_open)


func _gapped_score(total_with_gap: int) -> float:
	# Score for a gapped pattern (N stones across one gap).
	# Filling the gap creates N consecutive — score by resulting threat.
	# N>=4 → fill makes five (must block) = half_four.
	# N==3 → fill makes four (strong setup) = half_three.
	if total_with_gap >= 4:
		return weights["half_four"]
	if total_with_gap == 3:
		return weights["half_three"]
	return 0.0


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
