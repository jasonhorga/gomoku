class_name RenjuForbidden
extends RefCounted

const BOARD_SIZE: int = 15
const EMPTY: int = 0
const BLACK: int = 1
const WHITE: int = 2
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(0, 1),
	Vector2i(1, 0),
	Vector2i(1, 1),
	Vector2i(1, -1),
]


func is_forbidden_black(board: Array, row: int, col: int) -> bool:
	if not _is_inside(row, col):
		return false
	if board[row][col] != EMPTY:
		return false

	board[row][col] = BLACK
	var exact_five: bool = _has_exact_five(board, row, col)
	var overline: bool = _has_overline(board, row, col)
	var open_three_count: int = 0
	var four_count: int = 0

	if not exact_five:
		for dir in DIRECTIONS:
			if _line_has_four(board, row, col, dir):
				four_count += 1
			if _line_has_open_three(board, row, col, dir):
				open_three_count += 1

	board[row][col] = EMPTY

	if exact_five:
		return false
	if overline:
		return true
	if four_count >= 2:
		return true
	return open_three_count >= 2


func is_exact_five_for_black(board: Array, row: int, col: int) -> bool:
	if not _is_inside(row, col):
		return false
	if board[row][col] != BLACK:
		return false
	return _has_exact_five(board, row, col)


func _has_exact_five(board: Array, row: int, col: int) -> bool:
	for dir in DIRECTIONS:
		if _count_line(board, row, col, dir, BLACK) == 5:
			return true
	return false


func _has_overline(board: Array, row: int, col: int) -> bool:
	for dir in DIRECTIONS:
		if _count_line(board, row, col, dir, BLACK) >= 6:
			return true
	return false


func _count_line(board: Array, row: int, col: int, dir: Vector2i, player: int) -> int:
	var count: int = 1
	count += _count_dir(board, row, col, dir.x, dir.y, player)
	count += _count_dir(board, row, col, -dir.x, -dir.y, player)
	return count


func _count_dir(board: Array, row: int, col: int, dr: int, dc: int, player: int) -> int:
	var count: int = 0
	var r: int = row + dr
	var c: int = col + dc
	while _is_inside(r, c) and board[r][c] == player:
		count += 1
		r += dr
		c += dc
	return count


func _line_has_four(board: Array, row: int, col: int, dir: Vector2i) -> bool:
	var empties: Array[Vector2i] = _window_empty_cells(board, row, col, dir)
	for p in empties:
		board[p.x][p.y] = BLACK
		var makes_five: bool = _count_line(board, p.x, p.y, dir, BLACK) == 5
		board[p.x][p.y] = EMPTY
		if makes_five:
			return true
	return false


func _line_has_open_three(board: Array, row: int, col: int, dir: Vector2i) -> bool:
	var empties: Array[Vector2i] = _window_empty_cells(board, row, col, dir)
	for p in empties:
		board[p.x][p.y] = BLACK
		var creates_open_four: bool = _line_has_straight_open_four(board, p.x, p.y, dir)
		board[p.x][p.y] = EMPTY
		if creates_open_four:
			return true
	return false


func _line_has_straight_open_four(board: Array, row: int, col: int, dir: Vector2i) -> bool:
	var run_start: Vector2i = Vector2i(row, col)
	while _is_inside(run_start.x - dir.x, run_start.y - dir.y) and board[run_start.x - dir.x][run_start.y - dir.y] == BLACK:
		run_start = Vector2i(run_start.x - dir.x, run_start.y - dir.y)

	var run_end: Vector2i = Vector2i(row, col)
	while _is_inside(run_end.x + dir.x, run_end.y + dir.y) and board[run_end.x + dir.x][run_end.y + dir.y] == BLACK:
		run_end = Vector2i(run_end.x + dir.x, run_end.y + dir.y)

	var length: int = 1
	var cur: Vector2i = run_start
	while cur != run_end:
		length += 1
		cur = Vector2i(cur.x + dir.x, cur.y + dir.y)

	if length != 4:
		return false

	var before: Vector2i = Vector2i(run_start.x - dir.x, run_start.y - dir.y)
	var after: Vector2i = Vector2i(run_end.x + dir.x, run_end.y + dir.y)
	if not _is_inside(before.x, before.y) or not _is_inside(after.x, after.y):
		return false
	if board[before.x][before.y] != EMPTY or board[after.x][after.y] != EMPTY:
		return false

	board[before.x][before.y] = BLACK
	var before_exact: bool = _count_line(board, before.x, before.y, dir, BLACK) == 5
	board[before.x][before.y] = EMPTY

	board[after.x][after.y] = BLACK
	var after_exact: bool = _count_line(board, after.x, after.y, dir, BLACK) == 5
	board[after.x][after.y] = EMPTY

	return before_exact and after_exact


func _window_empty_cells(board: Array, row: int, col: int, dir: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset in range(-4, 5):
		var r: int = row + dir.x * offset
		var c: int = col + dir.y * offset
		if _is_inside(r, c) and board[r][c] == EMPTY:
			result.append(Vector2i(r, c))
	return result


func _is_inside(row: int, col: int) -> bool:
	return row >= 0 and row < BOARD_SIZE and col >= 0 and col < BOARD_SIZE
