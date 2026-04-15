extends "res://scripts/ai/ai_engine.gd"

const MCTSNode = preload("res://scripts/ai/mcts_node.gd")

var simulation_count: int = 1500
var exploration_constant: float = 1.414
var evaluator = preload("res://scripts/ai/pattern_evaluator.gd").new()


func _init(sims: int = 1500) -> void:
	simulation_count = sims


func choose_move(board: Array, current_player: int, move_history: Array) -> Vector2i:
	var opponent: int = BLACK if current_player == WHITE else WHITE
	var candidates = _get_candidate_moves(board)

	# Immediate win check
	for pos in candidates:
		board[pos.x][pos.y] = current_player
		if _check_win(board, pos.x, pos.y, current_player):
			board[pos.x][pos.y] = EMPTY
			return pos
		board[pos.x][pos.y] = EMPTY

	# Immediate block check
	for pos in candidates:
		board[pos.x][pos.y] = opponent
		if _check_win(board, pos.x, pos.y, opponent):
			board[pos.x][pos.y] = EMPTY
			return pos
		board[pos.x][pos.y] = EMPTY

	var root = MCTSNode.new(null, Vector2i(-1, -1), opponent)
	root.untried_moves = candidates

	for _i in range(simulation_count):
		# Deep copy board for this simulation
		var sim_board: Array = _copy_board(board)
		var sim_player: int = current_player

		# 1. Selection
		var node = root
		while node.is_fully_expanded() and not node.children.is_empty():
			node = node.best_child(exploration_constant)
			sim_board[node.move.x][node.move.y] = sim_player
			sim_player = BLACK if sim_player == WHITE else WHITE

		# 2. Expansion
		if not node.untried_moves.is_empty():
			var move_idx: int = randi() % node.untried_moves.size()
			var move: Vector2i = node.untried_moves[move_idx]
			node.untried_moves.remove_at(move_idx)

			sim_board[move.x][move.y] = sim_player
			var child = MCTSNode.new(node, move, sim_player)
			child.untried_moves = _get_candidate_moves(sim_board)
			node.children.append(child)
			node = child
			sim_player = BLACK if sim_player == WHITE else WHITE

		# 3. Simulation (rollout)
		var result: int = _simulate(sim_board, sim_player)

		# 4. Backpropagation
		while node != null:
			node.visits += 1
			if result == node.player:
				node.wins += 1.0
			elif result == EMPTY:
				node.wins += 0.5  # draw
			node = node.parent

	# Choose most visited child
	var best = root.most_visited_child()
	if best == null:
		return Vector2i(7, 7)
	return best.move


func _simulate(board: Array, current_player: int) -> int:
	# Semi-random rollout with heuristic guidance
	var player: int = current_player

	for _step in range(40):  # max 40 moves in rollout
		var candidates = _get_candidate_moves(board)
		if candidates.is_empty():
			return EMPTY  # draw

		var move: Vector2i = _choose_rollout_move(board, candidates, player)
		board[move.x][move.y] = player

		if _check_win(board, move.x, move.y, player):
			return player

		player = BLACK if player == WHITE else WHITE

	return EMPTY  # timeout = draw


func _choose_rollout_move(board: Array, candidates: Array, player: int) -> Vector2i:
	var opponent: int = BLACK if player == WHITE else WHITE

	# Check for immediate win
	for pos in candidates:
		board[pos.x][pos.y] = player
		if _check_win(board, pos.x, pos.y, player):
			board[pos.x][pos.y] = EMPTY
			return pos
		board[pos.x][pos.y] = EMPTY

	# Check for opponent's immediate win (must block)
	for pos in candidates:
		board[pos.x][pos.y] = opponent
		if _check_win(board, pos.x, pos.y, opponent):
			board[pos.x][pos.y] = EMPTY
			return pos
		board[pos.x][pos.y] = EMPTY

	# Otherwise random
	return candidates[randi() % candidates.size()]


func _get_candidate_moves(board: Array) -> Array:
	# Get empty cells near existing stones
	var candidates = get_nearby_empty_cells(board, 1)
	if candidates.size() < 5:
		# Expand search radius if few candidates
		candidates = get_nearby_empty_cells(board, 2)
	return candidates


func _copy_board(board: Array) -> Array:
	var copy: Array = []
	for row in board:
		copy.append(row.duplicate())
	return copy


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
	return "MCTS(%d)" % simulation_count
