extends RefCounted

var parent  # MCTSNode or null
var children: Array = []  # Array of MCTSNode
var move: Vector2i
var player: int  # who made this move
var visits: int = 0
var wins: float = 0.0
var prior: float = 0.0  # pattern-based prior probability


func _init(p_parent, p_move: Vector2i, p_player: int, p_prior: float = 0.0) -> void:
	parent = p_parent
	move = p_move
	player = p_player
	prior = p_prior


func puct(c: float) -> float:
	# PUCT selection: Q + c * prior * sqrt(parent_visits) / (1 + visits)
	var q: float = wins / maxf(visits, 1)
	return q + c * prior * sqrt(float(parent.visits)) / (1.0 + visits)


func best_child(c: float):
	var best = null
	var best_val: float = -INF
	for child in children:
		var val: float = child.puct(c)
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
