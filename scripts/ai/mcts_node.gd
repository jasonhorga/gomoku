extends RefCounted

var parent  # MCTSNode or null
var children: Array = []  # Array of MCTSNode
var move: Vector2i
var player: int  # who made this move
var visits: int = 0
var wins: float = 0.0
var untried_moves: Array = []  # Array[Vector2i]


func _init(p_parent, p_move: Vector2i, p_player: int) -> void:
	parent = p_parent
	move = p_move
	player = p_player


func ucb1(exploration: float) -> float:
	if visits == 0:
		return INF
	return (wins / visits) + exploration * sqrt(log(parent.visits) / visits)


func is_fully_expanded() -> bool:
	return untried_moves.is_empty()


func best_child(exploration: float):
	var best = null
	var best_val: float = -INF
	for child in children:
		var val: float = child.ucb1(exploration)
		if val > best_val:
			best_val = val
			best = child
	return best


func most_visited_child():
	var best = null
	var best_visits: int = -1
	for child in children:
		if child.visits > best_visits:
			best_visits = child.visits
			best = child
	return best
