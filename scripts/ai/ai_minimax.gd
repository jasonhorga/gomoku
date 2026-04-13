extends "res://scripts/ai/ai_engine.gd"

var evaluator = preload("res://scripts/ai/pattern_evaluator.gd").new()
var max_depth: int = 2
var use_iterative_deepening: bool = false
var zobrist = preload("res://scripts/ai/zobrist.gd").new()
var transposition_table: Dictionary = {}
var killer_moves: Array = []  # [depth] = [move1, move2]

const TT_EXACT: int = 0
const TT_LOWER: int = 1
const TT_UPPER: int = 2
const MAX_CANDIDATES: int = 20


func _init(depth: int = 2) -> void:
	max_depth = depth
	use_iterative_deepening = (depth >= 4)


func choose_move(board: Array, current_player: int, move_history: Array) -> Vector2i:
	transposition_table.clear()
	killer_moves.clear()
	for i in range(max_depth + 1):
		killer_moves.append([Vector2i(-1, -1), Vector2i(-1, -1)])

	# Initialize zobrist hash from board
	zobrist.reset()
	for r in range(BOARD_SIZE):
		for c in range(BOARD_SIZE):
			if board[r][c] != EMPTY:
				zobrist.update(r, c, board[r][c])

	var candidates = _get_sorted_candidates(board, current_player)
	if candidates.is_empty():
		return Vector2i(7, 7)

	# Check for immediate win
	for item in candidates:
		var pos: Vector2i = item.pos
		board[pos.x][pos.y] = current_player
		if _check_win(board, pos.x, pos.y, current_player):
			board[pos.x][pos.y] = EMPTY
			return pos
		board[pos.x][pos.y] = EMPTY

	if use_iterative_deepening:
		return _iterative_deepening_search(board, current_player, candidates)
	else:
		return _fixed_depth_search(board, current_player, candidates, max_depth)


func _iterative_deepening_search(board: Array, current_player: int, candidates: Array) -> Vector2i:
	var best_move: Vector2i = candidates[0].pos
	var opponent: int = BLACK if current_player == WHITE else WHITE

	for depth in range(1, max_depth + 1):
		var move = _fixed_depth_search(board, current_player, candidates, depth)
		best_move = move
		# Reorder candidates: put best move first for next iteration
		for i in range(candidates.size()):
			if candidates[i].pos == best_move:
				var tmp = candidates[i]
				candidates.remove_at(i)
				candidates.insert(0, tmp)
				break

	return best_move


func _fixed_depth_search(board: Array, current_player: int, candidates: Array, depth: int) -> Vector2i:
	var best_move: Vector2i = candidates[0].pos
	var best_score: float = -INF
	var alpha: float = -INF
	var beta: float = INF
	var opponent: int = BLACK if current_player == WHITE else WHITE

	for item in candidates:
		var pos: Vector2i = item.pos
		board[pos.x][pos.y] = current_player
		zobrist.update(pos.x, pos.y, current_player)

		var score: float = _minimax(board, depth - 1, alpha, beta, false, current_player, opponent, 1)

		zobrist.update(pos.x, pos.y, current_player)
		board[pos.x][pos.y] = EMPTY

		if score > best_score:
			best_score = score
			best_move = pos
		alpha = maxf(alpha, score)

	return best_move


func _minimax(board: Array, depth: int, alpha: float, beta: float,
		is_maximizing: bool, player: int, opponent: int, ply: int) -> float:

	# Transposition table lookup
	var tt_key: int = zobrist.get_hash()
	if tt_key in transposition_table:
		var entry = transposition_table[tt_key]
		if entry.depth >= depth:
			if entry.flag == TT_EXACT:
				return entry.score
			elif entry.flag == TT_LOWER:
				alpha = maxf(alpha, entry.score)
			elif entry.flag == TT_UPPER:
				beta = minf(beta, entry.score)
			if alpha >= beta:
				return entry.score

	if depth == 0:
		return evaluator.evaluate_board(board, player)

	var current: int = player if is_maximizing else opponent
	var candidates = _get_sorted_candidates(board, current)

	# Try killer moves first
	if ply < killer_moves.size():
		for km in killer_moves[ply]:
			if km.x >= 0 and board[km.x][km.y] == EMPTY:
				# Move killer to front
				for i in range(candidates.size()):
					if candidates[i].pos == km:
						var tmp = candidates[i]
						candidates.remove_at(i)
						candidates.insert(0, tmp)
						break

	var orig_alpha: float = alpha
	var best_score: float
	var best_move: Vector2i = Vector2i(-1, -1)

	if is_maximizing:
		best_score = -INF
		for item in candidates:
			var pos: Vector2i = item.pos
			board[pos.x][pos.y] = current
			zobrist.update(pos.x, pos.y, current)

			var score: float
			if _check_win(board, pos.x, pos.y, current):
				score = 100000.0 + depth  # prefer faster wins
			else:
				score = _minimax(board, depth - 1, alpha, beta, false, player, opponent, ply + 1)

			zobrist.update(pos.x, pos.y, current)
			board[pos.x][pos.y] = EMPTY

			if score > best_score:
				best_score = score
				best_move = pos
			alpha = maxf(alpha, score)
			if beta <= alpha:
				_store_killer(ply, pos)
				break
	else:
		best_score = INF
		for item in candidates:
			var pos: Vector2i = item.pos
			board[pos.x][pos.y] = current
			zobrist.update(pos.x, pos.y, current)

			var score: float
			if _check_win(board, pos.x, pos.y, current):
				score = -100000.0 - depth
			else:
				score = _minimax(board, depth - 1, alpha, beta, true, player, opponent, ply + 1)

			zobrist.update(pos.x, pos.y, current)
			board[pos.x][pos.y] = EMPTY

			if score < best_score:
				best_score = score
				best_move = pos
			beta = minf(beta, score)
			if beta <= alpha:
				_store_killer(ply, pos)
				break

	# Store in transposition table
	var flag: int = TT_EXACT
	if best_score <= orig_alpha:
		flag = TT_UPPER
	elif best_score >= beta:
		flag = TT_LOWER
	transposition_table[tt_key] = {"depth": depth, "score": best_score, "flag": flag, "move": best_move}

	return best_score


func _get_sorted_candidates(board: Array, current_player: int) -> Array:
	var raw = get_nearby_empty_cells(board, 2)
	var scored: Array = []
	for pos in raw:
		var s: float = evaluator.score_cell(board, pos.x, pos.y, current_player)
		scored.append({"pos": pos, "score": s})
	scored.sort_custom(func(a, b): return a.score > b.score)
	if scored.size() > MAX_CANDIDATES:
		scored.resize(MAX_CANDIDATES)
	return scored


func _store_killer(ply: int, move: Vector2i) -> void:
	if ply < killer_moves.size():
		if killer_moves[ply][0] != move:
			killer_moves[ply][1] = killer_moves[ply][0]
			killer_moves[ply][0] = move


func _check_win(board: Array, row: int, col: int, p: int) -> bool:
	for dir in [Vector2i(0,1), Vector2i(1,0), Vector2i(1,1), Vector2i(1,-1)]:
		var count: int = 1
		for sign in [1, -1]:
			var r: int = row + dir.x * sign
			var c: int = col + dir.y * sign
			while r >= 0 and r < BOARD_SIZE and c >= 0 and c < BOARD_SIZE and board[r][c] == p:
				count += 1
				r += dir.x * sign
				c += dir.y * sign
		if count >= 5:
			return true
	return false


func get_name() -> String:
	if use_iterative_deepening:
		return "Minimax(ID-d%d)" % max_depth
	return "Minimax(d%d)" % max_depth
