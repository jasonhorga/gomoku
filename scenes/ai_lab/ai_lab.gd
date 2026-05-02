extends Control

const _GameLogic = preload("res://scripts/game_logic.gd")
const _GameRecord = preload("res://scripts/data/game_record.gd")

const LEVEL_NAMES: Array[String] = ["L1 随机 ★", "L2 启发 ★★", "L3 搜索 ★★★", "L4 强搜索 ★★★★", "L5 蒙特卡洛 ★★★★", "L6 神经网络 ★★★★★"]
const SPEED_NAMES: Array[String] = ["即时", "快", "普通", "慢"]
const SPEED_VALUES: Array[float] = [0.0, 0.1, 0.5, 2.0]

@onready var black_level: OptionButton = %BlackLevel
@onready var white_level: OptionButton = %WhiteLevel
@onready var speed_slider: HSlider = %SpeedSlider
@onready var speed_text: Label = %SpeedText
@onready var renju_checkbox: CheckBox = %RenjuCheckBox
@onready var replay_last_batch_button: Button = %ReplayLastBatchButton
@onready var stats_label: Label = %StatsLabel

var batch_running: bool = false
var batch_total: int = 0
var batch_done: int = 0
var batch_wins_b: int = 0
var batch_wins_w: int = 0
var batch_use_renju_rules: bool = false
var last_batch_record_path: String = ""


func _ready() -> void:
	for name in LEVEL_NAMES:
		black_level.add_item(name)
		white_level.add_item(name)
	black_level.selected = 3  # L4 Minimax+
	white_level.selected = 4  # L5 MCTS

	speed_slider.value_changed.connect(_on_speed_changed)
	%WatchButton.pressed.connect(_on_watch_pressed)
	%RunBatchButton.pressed.connect(_on_run_batch_pressed)
	replay_last_batch_button.pressed.connect(_on_replay_last_batch_pressed)
	%BackButton.pressed.connect(_on_back_pressed)

	_update_stats()


func _on_speed_changed(val: float) -> void:
	speed_text.text = SPEED_NAMES[int(val)]


func _create_engine(level_idx: int):
	match level_idx:
		0: return load("res://scripts/ai/ai_random.gd").new()
		1: return load("res://scripts/ai/ai_heuristic.gd").new()
		2: return load("res://scripts/ai/ai_minimax.gd").new(2)
		3: return load("res://scripts/ai/ai_minimax.gd").new(4)
		4:
			# L5 = pattern-MCTS via Swift plugin. Linux editor → degrade to L4.
			if Engine.has_singleton("GomokuNeural"):
				return load("res://scripts/ai/ai_plugin_wrapper.gd").new(5)
			return load("res://scripts/ai/ai_minimax.gd").new(4)
		5: return load("res://scripts/ai/ai_neural.gd").new()
		_: return load("res://scripts/ai/ai_random.gd").new()


func _on_watch_pressed() -> void:
	var engine_b = _create_engine(black_level.selected)
	var engine_w = _create_engine(white_level.selected)
	GameManager.setup_ai_vs_ai(engine_b, engine_w, renju_checkbox.button_pressed)
	GameManager.ai_move_delay = SPEED_VALUES[int(speed_slider.value)]
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")


func _on_run_batch_pressed() -> void:
	if batch_running:
		return
	batch_running = true
	batch_total = int(%GamesSpinBox.value)
	batch_done = 0
	batch_wins_b = 0
	batch_wins_w = 0
	batch_use_renju_rules = renju_checkbox.button_pressed
	last_batch_record_path = ""
	replay_last_batch_button.disabled = true
	%RunBatchButton.disabled = true
	renju_checkbox.disabled = true
	stats_label.text = "批量进度：0/%d..." % batch_total
	_run_next_batch_game()


func _run_next_batch_game() -> void:
	if batch_done >= batch_total:
		batch_running = false
		%RunBatchButton.disabled = false
		renju_checkbox.disabled = false
		if not last_batch_record_path.is_empty():
			replay_last_batch_button.disabled = false
		stats_label.text = "完成：黑=%d 白=%d 平=%d | 总记录：%d" % [
			batch_wins_b, batch_wins_w, batch_total - batch_wins_b - batch_wins_w,
			_GameRecord.list_records().size()]
		return

	# Color alternation: on odd-indexed games, swap the two selected
	# engines so each side plays both black (first-move advantage) and
	# white. Without this, a batch comparing L4 vs L5 sees L5 as white
	# for every game and first-move bias dominates the score.
	var swap_colors: bool = (batch_done % 2 == 1)
	var engine_b
	var engine_w
	if swap_colors:
		engine_b = _create_engine(white_level.selected)
		engine_w = _create_engine(black_level.selected)
	else:
		engine_b = _create_engine(black_level.selected)
		engine_w = _create_engine(white_level.selected)

	# Run a headless game using game logic directly
	var use_renju_rules: bool = batch_use_renju_rules
	var logic = _GameLogic.new()
	logic.forbidden_enabled = use_renju_rules
	if "forbidden_enabled" in engine_b:
		engine_b.forbidden_enabled = use_renju_rules
	if "forbidden_enabled" in engine_w:
		engine_w.forbidden_enabled = use_renju_rules
	var current = _GameLogic.BLACK

	while not logic.game_over:
		# Yield each turn — a single choose_move can run ~0.5-3s on
		# iPhone, and 20-move games × synchronous calls used to starve
		# the main thread for ~10s. iOS's scene-update watchdog fires
		# 0x8BADF00D at 10s while backgrounded; after this yield we
		# process a frame per move so the OS stays happy.
		await get_tree().process_frame

		var board_copy: Array = []
		for row in logic.board:
			board_copy.append(row.duplicate())

		var move: Vector2i
		if current == _GameLogic.BLACK:
			move = engine_b.choose_move(board_copy, current, logic.move_history.duplicate())
		else:
			move = engine_w.choose_move(board_copy, current, logic.move_history.duplicate())

		if not logic.place_stone(move.x, move.y):
			break  # invalid move, abort game
		current = _GameLogic.WHITE if current == _GameLogic.BLACK else _GameLogic.BLACK

	# Save record
	var record = _GameRecord.new()
	record.timestamp = Time.get_datetime_string_from_system().replace("T", "_").replace(":", "-") + "_%03d" % batch_done
	record.mode = "ai_vs_ai"
	record.black_type = "ai_" + engine_b.get_name().to_lower()
	record.white_type = "ai_" + engine_w.get_name().to_lower()
	record.ruleset = "renju" if use_renju_rules else "free"
	record.result = logic.winner
	record.total_moves = logic.move_history.size()
	for m in logic.move_history:
		record.moves.append([m.x, m.y])
	var path = _GameRecord.get_records_dir() + "/" + record.timestamp + ".json"
	if _GameRecord.save_to_file(record, path):
		last_batch_record_path = path

	# Attribute the win to the SELECTED dropdown level, not the board
	# colour, so the tally is meaningful when colors alternate each game.
	# batch_wins_b = wins by the engine in the "Black" dropdown;
	# batch_wins_w = wins by the engine in the "White" dropdown.
	var winner_is_black_level: bool
	if swap_colors:
		winner_is_black_level = (logic.winner == _GameLogic.WHITE)
	else:
		winner_is_black_level = (logic.winner == _GameLogic.BLACK)
	if logic.winner != _GameLogic.EMPTY:
		if winner_is_black_level:
			batch_wins_b += 1
		else:
			batch_wins_w += 1

	batch_done += 1
	stats_label.text = "进度：%d/%d (%s:%d %s:%d)" % [
		batch_done, batch_total,
		LEVEL_NAMES[black_level.selected], batch_wins_b,
		LEVEL_NAMES[white_level.selected], batch_wins_w
	]

	# Use call_deferred to avoid stack overflow and allow UI updates
	_run_next_batch_game.call_deferred()



func _update_stats() -> void:
	var count = _GameRecord.list_records().size()
	stats_label.text = "记录：%d | 就绪" % count


func _on_replay_last_batch_pressed() -> void:
	if last_batch_record_path.is_empty():
		replay_last_batch_button.disabled = true
		return
	if not GameManager.prepare_replay_from_path(last_batch_record_path):
		stats_label.text = "无法载入复盘：%s" % last_batch_record_path.get_file()
		replay_last_batch_button.disabled = true
		return
	GameManager.replay_return_scene = "res://scenes/ai_lab/ai_lab.tscn"
	get_tree().change_scene_to_file("res://scenes/replay/replay.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
