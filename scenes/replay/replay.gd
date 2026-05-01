extends Control

const _GameLogic = preload("res://scripts/game_logic.gd")

@onready var status_label: Label = %StatusLabel
@onready var board: Node2D = %Board
@onready var prev_button: Button = %PrevButton
@onready var next_button: Button = %NextButton
@onready var start_button: Button = %StartButton
@onready var play_button: Button = %PlayButton
@onready var back_button: Button = %BackButton

var record = null
var cursor: int = 0
var _playing: bool = false
var _play_epoch: int = 0


func _ready() -> void:
	record = GameManager.replay_record
	prev_button.pressed.connect(_on_prev_pressed)
	next_button.pressed.connect(_on_next_pressed)
	start_button.pressed.connect(_on_start_pressed)
	play_button.pressed.connect(_on_play_pressed)
	back_button.pressed.connect(_on_back_pressed)
	board.read_only = true
	if record == null:
		cursor = 0
		_update_view()
		return
	cursor = _move_count()
	_update_view()


func _exit_tree() -> void:
	_play_epoch += 1
	_playing = false


func _make_empty_board() -> Array:
	var empty_board: Array = []
	for _r in range(_GameLogic.BOARD_SIZE):
		var row: Array = []
		for _c in range(_GameLogic.BOARD_SIZE):
			row.append(_GameLogic.EMPTY)
		empty_board.append(row)
	return empty_board


func _move_count() -> int:
	if record == null:
		return 0
	return record.moves.size()


func _update_view() -> void:
	board.display_board = _build_board_to_cursor()
	board.display_last_move = _display_last_move()
	_update_status()
	_update_buttons()
	board.queue_redraw()


func _display_last_move() -> Vector2i:
	if record == null or cursor <= 0:
		return Vector2i(-1, -1)
	var move: Variant = record.moves[mini(cursor, _move_count()) - 1]
	var row: int = _move_row(move)
	var col: int = _move_col(move)
	if row < 0 or row >= _GameLogic.BOARD_SIZE or col < 0 or col >= _GameLogic.BOARD_SIZE:
		return Vector2i(-1, -1)
	return Vector2i(row, col)


func _build_board_to_cursor() -> Array:
	var board_data: Array = _make_empty_board()
	if record == null:
		return board_data
	var color: int = _GameLogic.BLACK
	var limit: int = clampi(cursor, 0, _move_count())
	for i in range(limit):
		var move: Variant = record.moves[i]
		var row: int = _move_row(move)
		var col: int = _move_col(move)
		if row < 0 or row >= _GameLogic.BOARD_SIZE or col < 0 or col >= _GameLogic.BOARD_SIZE:
			continue
		if board_data[row][col] != _GameLogic.EMPTY:
			continue
		board_data[row][col] = color
		color = _GameLogic.WHITE if color == _GameLogic.BLACK else _GameLogic.BLACK
	return board_data


func _move_row(move: Variant) -> int:
	if move is Vector2i:
		return move.x
	if move is Vector2:
		return int(move.x)
	if move is Array and move.size() >= 2:
		return int(move[0])
	return -1


func _move_col(move: Variant) -> int:
	if move is Vector2i:
		return move.y
	if move is Vector2:
		return int(move.y)
	if move is Array and move.size() >= 2:
		return int(move[1])
	return -1


func _update_status() -> void:
	if record == null:
		status_label.text = "没有可复盘的棋局"
		return
	var result_text: String = "平局"
	if record.result == _GameLogic.BLACK:
		result_text = "黑胜"
	elif record.result == _GameLogic.WHITE:
		result_text = "白胜"
	var rules_text: String = "禁手" if record.ruleset == "renju" else "自由规则"
	status_label.text = "%s｜%s vs %s｜%d/%d｜%s" % [
		rules_text,
		_friendly_type(record.black_type),
		_friendly_type(record.white_type),
		cursor,
		_move_count(),
		result_text,
	]


func _friendly_type(type_name: String) -> String:
	if type_name == "human":
		return "玩家"
	if type_name.begins_with("ai_"):
		return type_name.replace("ai_", "AI ").to_upper()
	if type_name == "network":
		return "在线玩家"
	return type_name


func _update_buttons() -> void:
	var has_record: bool = record != null and _move_count() > 0
	prev_button.disabled = not has_record or cursor <= 0
	start_button.disabled = not has_record or cursor <= 0
	next_button.disabled = not has_record or cursor >= _move_count()
	play_button.disabled = not has_record
	play_button.text = "暂停" if _playing else "播放"


func _on_prev_pressed() -> void:
	_stop_playback()
	cursor = maxi(0, cursor - 1)
	_update_view()


func _on_next_pressed() -> void:
	_stop_playback()
	_step_forward()


func _on_start_pressed() -> void:
	_stop_playback()
	cursor = 0
	_update_view()


func _on_play_pressed() -> void:
	if record == null or _move_count() == 0:
		return
	if _playing:
		_stop_playback()
		_update_buttons()
		return
	if cursor >= _move_count():
		cursor = 0
		_update_view()
	_playing = true
	_play_epoch += 1
	_update_buttons()
	_play_loop(_play_epoch)


func _step_forward() -> void:
	cursor = mini(_move_count(), cursor + 1)
	_update_view()


func _stop_playback() -> void:
	if _playing:
		_play_epoch += 1
	_playing = false


func _play_loop(epoch: int) -> void:
	while _playing and epoch == _play_epoch and cursor < _move_count():
		await get_tree().create_timer(0.55).timeout
		if not _playing or epoch != _play_epoch:
			return
		_step_forward()
	_playing = false
	_update_buttons()


func _on_back_pressed() -> void:
	_stop_playback()
	var return_scene: String = GameManager.replay_return_scene
	if return_scene.is_empty():
		return_scene = "res://scenes/main_menu/main_menu.tscn"
	get_tree().change_scene_to_file(return_scene)
