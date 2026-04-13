class_name GameLogic
extends RefCounted

const BOARD_SIZE: int = 15
const EMPTY: int = 0
const BLACK: int = 1
const WHITE: int = 2

var board: Array = []
var current_player: int = BLACK
var move_history: Array[Vector2i] = []
var game_over: bool = false
var winner: int = EMPTY


func _init() -> void:
	reset()


func reset() -> void:
	board.clear()
	for row in range(BOARD_SIZE):
		var line: Array = []
		line.resize(BOARD_SIZE)
		line.fill(EMPTY)
		board.append(line)
	current_player = BLACK
	move_history.clear()
	game_over = false
	winner = EMPTY


func place_stone(row: int, col: int) -> bool:
	if game_over:
		return false
	if row < 0 or row >= BOARD_SIZE or col < 0 or col >= BOARD_SIZE:
		return false
	if board[row][col] != EMPTY:
		return false

	board[row][col] = current_player
	move_history.append(Vector2i(row, col))

	if _check_win(row, col):
		game_over = true
		winner = current_player
	elif move_history.size() >= BOARD_SIZE * BOARD_SIZE:
		game_over = true
		winner = EMPTY  # draw

	current_player = WHITE if current_player == BLACK else BLACK
	return true


func _check_win(row: int, col: int) -> bool:
	var player: int = board[row][col]
	# Four directions: horizontal, vertical, diagonal-down-right, diagonal-down-left
	var directions: Array[Vector2i] = [
		Vector2i(0, 1),   # horizontal
		Vector2i(1, 0),   # vertical
		Vector2i(1, 1),   # diagonal ↘
		Vector2i(1, -1),  # diagonal ↙
	]
	for dir in directions:
		var count: int = 1
		count += _count_in_direction(row, col, dir.x, dir.y, player)
		count += _count_in_direction(row, col, -dir.x, -dir.y, player)
		if count >= 5:
			return true
	return false


func _count_in_direction(row: int, col: int, dr: int, dc: int, player: int) -> int:
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
	return count


func get_last_move() -> Vector2i:
	if move_history.is_empty():
		return Vector2i(-1, -1)
	return move_history.back()
