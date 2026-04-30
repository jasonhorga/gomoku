extends RefCounted

const BOARD_SIZE: int = 15
const EMPTY: int = 0
const BLACK: int = 1
const WHITE: int = 2
const _RenjuForbidden = preload("res://scripts/rules/renju_forbidden.gd")

var forbidden_enabled: bool = false
var forbidden_checker = _RenjuForbidden.new()


func choose_move(board: Array, current_player: int, move_history: Array) -> Vector2i:
	# Override in subclasses. Returns Vector2i(row, col).
	return Vector2i(-1, -1)


func get_name() -> String:
	return "BaseAI"


func filter_legal_candidates(board: Array, current_player: int, candidates: Array[Vector2i]) -> Array[Vector2i]:
	if not forbidden_enabled or current_player != BLACK:
		return candidates
	var legal: Array[Vector2i] = []
	for pos in candidates:
		if not forbidden_checker.is_forbidden_black(board, pos.x, pos.y):
			legal.append(pos)
	return legal


func get_any_legal_empty_cell(board: Array, current_player: int) -> Vector2i:
	for row in range(BOARD_SIZE):
		for col in range(BOARD_SIZE):
			if board[row][col] == EMPTY:
				var pos := Vector2i(row, col)
				var candidate: Array[Vector2i] = [pos]
				if not filter_legal_candidates(board, current_player, candidate).is_empty():
					return pos
	return Vector2i(-1, -1)


func first_legal_empty_cell(board: Array, current_player: int) -> Vector2i:
	return get_any_legal_empty_cell(board, current_player)


func get_nearby_empty_cells(board: Array, radius: int = 2) -> Array[Vector2i]:
	# Returns empty cells within 'radius' of any placed stone.
	# Used by all AI levels to avoid searching the entire board.
	var candidates: Array[Vector2i] = []
	var seen: Dictionary = {}

	for row in range(BOARD_SIZE):
		for col in range(BOARD_SIZE):
			if board[row][col] != EMPTY:
				for dr in range(-radius, radius + 1):
					for dc in range(-radius, radius + 1):
						var r: int = row + dr
						var c: int = col + dc
						if r >= 0 and r < BOARD_SIZE and c >= 0 and c < BOARD_SIZE:
							if board[r][c] == EMPTY:
								var key: int = r * BOARD_SIZE + c
								if key not in seen:
									seen[key] = true
									candidates.append(Vector2i(r, c))

	# If board is empty, play center. If no empty cells exist, return no candidates.
	if candidates.is_empty() and board[7][7] == EMPTY:
		candidates.append(Vector2i(7, 7))

	return candidates
