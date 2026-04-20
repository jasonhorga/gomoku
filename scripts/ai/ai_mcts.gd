extends "res://scripts/ai/ai_engine.gd"

const MCTSNode = preload("res://scripts/ai/mcts_node.gd")

var simulation_count: int = 1500
var c_puct: float = 2.5
var evaluator = preload("res://scripts/ai/pattern_evaluator.gd").new()


func _init(sims: int = 1500) -> void:
	simulation_count = sims


func choose_move(board: Array, current_player: int, move_history: Array) -> Vector2i:
	# iOS fast path: delegate to the Swift GomokuNeural plugin, which
	# runs the same pattern-guided MCTS natively (100x faster than
	# GDScript, lets us bump sims + VCF depth without hurting latency).
	# On platforms without the plugin (macOS / Linux editor) we fall
	# through to the pure-GDScript implementation below.
	if Engine.has_singleton("GomokuNeural"):
		var plugin = Engine.get_singleton("GomokuNeural")
		var last_move: Vector2i = move_history[-1] if not move_history.is_empty() else Vector2i(-1, -1)
		var result: Vector2i = plugin.get_move(5, board, current_player, last_move)
		Log.info("MCTS", "plugin L5 move=%s" % result)
		return result

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

	# Create root and expand with pattern priors
	var root = MCTSNode.new(null, Vector2i(-1, -1), opponent)
	_expand_node(root, board, current_player)

	if root.children.is_empty():
		return Vector2i(7, 7)

	for _i in range(simulation_count):
		var sim_board: Array = _copy_board(board)
		var sim_player: int = current_player

		# 1. Selection — traverse tree using PUCT
		var node = root
		while not node.children.is_empty():
			node = node.best_child(c_puct)
			sim_board[node.move.x][node.move.y] = sim_player
			sim_player = BLACK if sim_player == WHITE else WHITE

		# 2. Evaluate
		var value: float
		if node.move != Vector2i(-1, -1) and _check_win(sim_board, node.move.x, node.move.y, node.player):
			# Terminal: node.player just won
			value = 1.0 if node.player == current_player else 0.0
		else:
			# Expand leaf and evaluate position
			_expand_node(node, sim_board, sim_player)
			value = _evaluate_leaf(sim_board, current_player)

		# 3. Backpropagation
		while node != null:
			node.visits += 1
			if node.player == current_player:
				node.wins += value
			else:
				node.wins += 1.0 - value
			node = node.parent

	# Choose most visited child
	var best = root.most_visited_child()
	var chosen := best.move if best != null else Vector2i(7, 7)

	# Log a summary before tearing down the tree. Memory tracking is what we
	# need to diagnose the iOS crash — if peak mem creeps each move, something
	# here still leaks.
	var mem_mb := float(OS.get_static_memory_usage()) / (1024.0 * 1024.0)
	Log.info("MCTS", "sims=%d move=%s visits=%d mem=%.1fMB" % [
		simulation_count, chosen, (best.visits if best != null else 0), mem_mb
	])

	# Explicit tree teardown. Weak parent refs break the parent→children cycle,
	# but we still flush the children array to free nodes eagerly rather than
	# wait for root to go out of scope.
	_free_tree(root)

	return chosen


func _free_tree(node) -> void:
	if node == null:
		return
	for child in node.children:
		_free_tree(child)
	node.children.clear()


func _expand_node(node, board: Array, next_player: int) -> void:
	var candidates = _get_candidate_moves(board)
	if candidates.is_empty():
		return

	# Score each candidate with pattern evaluator
	var scores: Array[float] = []
	var total: float = 0.0
	for pos in candidates:
		var s: float = evaluator.score_cell(board, pos.x, pos.y, next_player) + 1.0
		scores.append(s)
		total += s

	# Create children with normalized priors
	for i in range(candidates.size()):
		var prior: float = scores[i] / total
		var child = MCTSNode.new(node, candidates[i], next_player, prior)
		node.children.append(child)


func _evaluate_leaf(board: Array, player: int) -> float:
	# Pattern-based position evaluation, mapped to 0-1
	var score: float = evaluator.evaluate_board(board, player)
	return (tanh(score / 1000.0) + 1.0) / 2.0


func _get_candidate_moves(board: Array) -> Array:
	var candidates = get_nearby_empty_cells(board, 1)
	if candidates.size() < 5:
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
