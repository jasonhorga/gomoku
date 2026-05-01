extends Node2D

const _GameLogic = preload("res://scripts/game_logic.gd")

const BOARD_SIZE: int = 15
const CELL_SIZE: float = 40.0
const MARGIN: float = 30.0
const BOARD_PIXEL_SIZE: float = CELL_SIZE * (BOARD_SIZE - 1) + MARGIN * 2.0
const STONE_RADIUS: float = 17.0
const GRID_COLOR: Color = Color(0.15, 0.1, 0.05, 0.9)
const GRID_LINE_WIDTH: float = 1.5

# Star points (hoshi) positions
const STAR_POINTS: Array[Vector2i] = [
	Vector2i(3, 3), Vector2i(3, 11),
	Vector2i(7, 7),
	Vector2i(11, 3), Vector2i(11, 11),
]

var hover_pos: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	GameManager.stone_placed.connect(_on_stone_placed)
	GameManager.game_reset.connect(_on_game_reset)
	GameManager.turn_changed.connect(_on_turn_changed)


func _on_stone_placed(_row: int, _col: int, _color: int) -> void:
	queue_redraw()


func _on_game_reset() -> void:
	queue_redraw()


func _on_turn_changed(_is_my_turn: bool) -> void:
	queue_redraw()


func _draw() -> void:
	_draw_grid()
	_draw_star_points()
	_draw_forbidden_markers()
	_draw_stones()
	_draw_last_move_marker()
	_draw_hover_preview()


func _draw_grid() -> void:
	for i in range(BOARD_SIZE):
		var offset: float = MARGIN + i * CELL_SIZE
		# Horizontal line
		draw_line(
			Vector2(MARGIN, offset),
			Vector2(MARGIN + (BOARD_SIZE - 1) * CELL_SIZE, offset),
			GRID_COLOR, GRID_LINE_WIDTH
		)
		# Vertical line
		draw_line(
			Vector2(offset, MARGIN),
			Vector2(offset, MARGIN + (BOARD_SIZE - 1) * CELL_SIZE),
			GRID_COLOR, GRID_LINE_WIDTH
		)


func _draw_star_points() -> void:
	for sp in STAR_POINTS:
		var pos: Vector2 = grid_to_pixel(sp.x, sp.y)
		draw_circle(pos, 4.0, GRID_COLOR)


func _draw_forbidden_markers() -> void:
	if not _should_show_forbidden_markers():
		return
	var board: Array = GameManager.logic.board
	for row in range(BOARD_SIZE):
		for col in range(BOARD_SIZE):
			if board[row][col] != _GameLogic.EMPTY:
				continue
			if GameManager.logic.is_forbidden_move(row, col, _GameLogic.BLACK):
				_draw_forbidden_marker(grid_to_pixel(row, col))


func _should_show_forbidden_markers() -> bool:
	if not GameManager.forbidden_enabled:
		return false
	if GameManager.logic.current_player != _GameLogic.BLACK:
		return false
	if GameManager.logic.game_over:
		return false
	if GameManager.mode == GameManager.GameMode.LOCAL_PVP:
		return true
	return GameManager.is_my_turn


func _draw_forbidden_marker(pos: Vector2) -> void:
	var marker_size: float = 7.0
	var marker_color: Color = Color(0.9, 0.05, 0.05, 0.9)
	var line_width: float = 2.0
	draw_line(
		pos + Vector2(-marker_size, -marker_size),
		pos + Vector2(marker_size, marker_size),
		marker_color,
		line_width
	)
	draw_line(
		pos + Vector2(marker_size, -marker_size),
		pos + Vector2(-marker_size, marker_size),
		marker_color,
		line_width
	)


func _draw_stones() -> void:
	var board: Array = GameManager.logic.board
	for row in range(BOARD_SIZE):
		for col in range(BOARD_SIZE):
			var cell: int = board[row][col]
			if cell == _GameLogic.EMPTY:
				continue
			var pos: Vector2 = grid_to_pixel(row, col)
			if cell == _GameLogic.BLACK:
				_draw_black_stone(pos)
			else:
				_draw_white_stone(pos)


func _draw_black_stone(pos: Vector2) -> void:
	# Shadow
	draw_circle(pos + Vector2(2, 2), STONE_RADIUS, Color(0, 0, 0, 0.3))
	# Base
	draw_circle(pos, STONE_RADIUS, Color(0.1, 0.1, 0.1))
	# Highlight
	draw_circle(pos + Vector2(-4, -4), STONE_RADIUS * 0.3, Color(0.35, 0.35, 0.35))


func _draw_white_stone(pos: Vector2) -> void:
	# Shadow
	draw_circle(pos + Vector2(2, 2), STONE_RADIUS, Color(0, 0, 0, 0.2))
	# Base
	draw_circle(pos, STONE_RADIUS, Color(0.95, 0.95, 0.93))
	# Edge ring
	draw_arc(pos, STONE_RADIUS - 1, 0, TAU, 64, Color(0.75, 0.75, 0.73), 1.5)
	# Highlight
	draw_circle(pos + Vector2(-4, -4), STONE_RADIUS * 0.3, Color(1.0, 1.0, 1.0))


func _draw_last_move_marker() -> void:
	var last: Vector2i = GameManager.logic.get_last_move()
	if last.x < 0:
		return
	var pos: Vector2 = grid_to_pixel(last.x, last.y)
	draw_rect(Rect2(pos - Vector2(6, 6), Vector2(12, 12)), Color.RED, false, 2.0)


func _draw_hover_preview() -> void:
	if hover_pos.x < 0 or not GameManager.is_my_turn or GameManager.logic.game_over:
		return
	if GameManager.logic.board[hover_pos.x][hover_pos.y] != _GameLogic.EMPTY:
		return
	var pos: Vector2 = grid_to_pixel(hover_pos.x, hover_pos.y)
	# In LOCAL_PVP, show current player's color; otherwise show my_color
	var stone_color: int = GameManager.logic.current_player if GameManager.my_color < 0 else GameManager.my_color
	var color: Color
	if stone_color == _GameLogic.BLACK:
		color = Color(0.1, 0.1, 0.1, 0.3)
	else:
		color = Color(0.95, 0.95, 0.93, 0.3)
	draw_circle(pos, STONE_RADIUS, color)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var new_hover: Vector2i = pixel_to_grid(event.position - global_position)
		if new_hover != hover_pos:
			hover_pos = new_hover
			queue_redraw()
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var grid_pos: Vector2i = pixel_to_grid(event.position - global_position)
			if grid_pos.x >= 0:
				GameManager.submit_human_move(grid_pos.x, grid_pos.y)


func grid_to_pixel(row: int, col: int) -> Vector2:
	return Vector2(MARGIN + col * CELL_SIZE, MARGIN + row * CELL_SIZE)


func pixel_to_grid(pixel: Vector2) -> Vector2i:
	var col: int = roundi((pixel.x - MARGIN) / CELL_SIZE)
	var row: int = roundi((pixel.y - MARGIN) / CELL_SIZE)
	if row < 0 or row >= BOARD_SIZE or col < 0 or col >= BOARD_SIZE:
		return Vector2i(-1, -1)
	# Check if click is close enough to the intersection
	var snap_pos: Vector2 = grid_to_pixel(row, col)
	if pixel.distance_to(snap_pos) > CELL_SIZE * 0.45:
		return Vector2i(-1, -1)
	return Vector2i(row, col)
