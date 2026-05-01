extends Node2D

const _GameLogic = preload("res://scripts/game_logic.gd")

const BOARD_SIZE: int = 15
const BASE_CELL_SIZE: float = 40.0
const BASE_MARGIN: float = 30.0
const BASE_BOARD_PIXEL_SIZE: float = BASE_CELL_SIZE * (BOARD_SIZE - 1) + BASE_MARGIN * 2.0
const BASE_STONE_RADIUS: float = 17.0
const GRID_COLOR: Color = Color(0.15, 0.1, 0.05, 0.9)
const GRID_LINE_WIDTH: float = 1.5

@export var board_pixel_size: float = BASE_BOARD_PIXEL_SIZE:
	set(value):
		board_pixel_size = value
		_apply_minimum_size_if_supported()
		_update_background_size()
		queue_redraw()

# Star points (hoshi) positions
const STAR_POINTS: Array[Vector2i] = [
	Vector2i(3, 3), Vector2i(3, 11),
	Vector2i(7, 7),
	Vector2i(11, 3), Vector2i(11, 11),
]

var hover_pos: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	_apply_minimum_size_if_supported()
	_update_background_size()
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


func _scale() -> float:
	return board_pixel_size / BASE_BOARD_PIXEL_SIZE


func _cell_size() -> float:
	return BASE_CELL_SIZE * _scale()


func _margin() -> float:
	return BASE_MARGIN * _scale()


func _stone_radius() -> float:
	return BASE_STONE_RADIUS * _scale()


func _apply_minimum_size_if_supported() -> void:
	var minimum_size := Vector2(board_pixel_size, board_pixel_size)
	if "custom_minimum_size" in self:
		set("custom_minimum_size", minimum_size)
		return
	var parent_control := get_parent() as Control
	if parent_control != null:
		parent_control.custom_minimum_size = minimum_size


func _update_background_size() -> void:
	var background: ColorRect = get_node_or_null("WoodBackground")
	if background == null:
		return
	background.offset_right = board_pixel_size
	background.offset_bottom = board_pixel_size


func _draw_grid() -> void:
	var margin: float = _margin()
	var cell_size: float = _cell_size()
	for i in range(BOARD_SIZE):
		var offset: float = margin + i * cell_size
		# Horizontal line
		draw_line(
			Vector2(margin, offset),
			Vector2(margin + (BOARD_SIZE - 1) * cell_size, offset),
			GRID_COLOR, GRID_LINE_WIDTH
		)
		# Vertical line
		draw_line(
			Vector2(offset, margin),
			Vector2(offset, margin + (BOARD_SIZE - 1) * cell_size),
			GRID_COLOR, GRID_LINE_WIDTH
		)


func _draw_star_points() -> void:
	for sp in STAR_POINTS:
		var pos: Vector2 = grid_to_pixel(sp.x, sp.y)
		draw_circle(pos, 4.0 * _scale(), GRID_COLOR)


func _draw_forbidden_markers() -> void:
	if not _should_show_forbidden_markers():
		return
	var board_data: Array = GameManager.logic.board
	for row in range(BOARD_SIZE):
		for col in range(BOARD_SIZE):
			if board_data[row][col] != _GameLogic.EMPTY:
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
	var marker_size: float = 7.0 * _scale()
	var marker_color: Color = Color(0.9, 0.05, 0.05, 0.9)
	var line_width: float = 2.0 * _scale()
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
	var board_data: Array = GameManager.logic.board
	for row in range(BOARD_SIZE):
		for col in range(BOARD_SIZE):
			var cell: int = board_data[row][col]
			if cell == _GameLogic.EMPTY:
				continue
			var pos: Vector2 = grid_to_pixel(row, col)
			if cell == _GameLogic.BLACK:
				_draw_black_stone(pos)
			else:
				_draw_white_stone(pos)


func _draw_black_stone(pos: Vector2) -> void:
	var stone_radius: float = _stone_radius()
	var shadow_offset: Vector2 = Vector2(2, 2) * _scale()
	# Shadow
	draw_circle(pos + shadow_offset, stone_radius, Color(0, 0, 0, 0.3))
	# Base
	draw_circle(pos, stone_radius, Color(0.1, 0.1, 0.1))
	# Highlight
	draw_circle(pos + Vector2(-4, -4) * _scale(), stone_radius * 0.3, Color(0.35, 0.35, 0.35))


func _draw_white_stone(pos: Vector2) -> void:
	var stone_radius: float = _stone_radius()
	var shadow_offset: Vector2 = Vector2(2, 2) * _scale()
	# Shadow
	draw_circle(pos + shadow_offset, stone_radius, Color(0, 0, 0, 0.2))
	# Base
	draw_circle(pos, stone_radius, Color(0.95, 0.95, 0.93))
	# Edge ring
	draw_arc(pos, stone_radius - _scale(), 0, TAU, 64, Color(0.75, 0.75, 0.73), 1.5 * _scale())
	# Highlight
	draw_circle(pos + Vector2(-4, -4) * _scale(), stone_radius * 0.3, Color(1.0, 1.0, 1.0))


func _draw_last_move_marker() -> void:
	var last: Vector2i = GameManager.logic.get_last_move()
	if last.x < 0:
		return
	var pos: Vector2 = grid_to_pixel(last.x, last.y)
	var marker_size: float = 6.0 * _scale()
	draw_rect(Rect2(pos - Vector2(marker_size, marker_size), Vector2(marker_size * 2.0, marker_size * 2.0)), Color.RED, false, 2.0 * _scale())


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
	draw_circle(pos, _stone_radius(), color)


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
	return Vector2(_margin() + col * _cell_size(), _margin() + row * _cell_size())


func pixel_to_grid(pixel: Vector2) -> Vector2i:
	var cell_size: float = _cell_size()
	var col: int = roundi((pixel.x - _margin()) / cell_size)
	var row: int = roundi((pixel.y - _margin()) / cell_size)
	if row < 0 or row >= BOARD_SIZE or col < 0 or col >= BOARD_SIZE:
		return Vector2i(-1, -1)
	# Check if click is close enough to the intersection
	var snap_pos: Vector2 = grid_to_pixel(row, col)
	if pixel.distance_to(snap_pos) > cell_size * 0.45:
		return Vector2i(-1, -1)
	return Vector2i(row, col)
