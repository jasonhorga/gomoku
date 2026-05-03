extends Control

const _GameLogic = preload("res://scripts/game_logic.gd")
const _GameRecord = preload("res://scripts/data/game_record.gd")

const LEVEL_NAMES: Array[String] = ["L1 随机 ★", "L2 启发 ★★", "L3 搜索 ★★★", "L4 强搜索 ★★★★", "L5 蒙特卡洛 ★★★★", "L6 神经网络 ★★★★★"]
const SPEED_NAMES: Array[String] = ["即时", "快", "普通", "慢"]
const SPEED_VALUES: Array[float] = [0.0, 0.1, 0.5, 2.0]

@onready var lab_container: VBoxContainer = $VBoxContainer
@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var match_row: BoxContainer = $VBoxContainer/MatchRow
@onready var black_level: OptionButton = %BlackLevel
@onready var white_level: OptionButton = %WhiteLevel
@onready var speed_row: HBoxContainer = $VBoxContainer/SpeedRow
@onready var speed_slider: HSlider = %SpeedSlider
@onready var speed_text: Label = %SpeedText
@onready var rules_selector: Control = %RulesSelector
@onready var action_row: BoxContainer = $VBoxContainer/ActionRow
@onready var watch_button: Button = %WatchButton
@onready var run_batch_button: Button = %RunBatchButton
@onready var replay_last_batch_button: Button = %ReplayLastBatchButton
@onready var back_button: Button = %BackButton
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
	watch_button.pressed.connect(_on_watch_pressed)
	run_batch_button.pressed.connect(_on_run_batch_pressed)
	replay_last_batch_button.pressed.connect(_on_replay_last_batch_pressed)
	back_button.pressed.connect(_on_back_pressed)
	get_viewport().size_changed.connect(_apply_phone_layout)

	_update_stats()
	_apply_phone_layout()


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
	GameManager.setup_ai_vs_ai(engine_b, engine_w, rules_selector.forbidden_enabled)
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
	batch_use_renju_rules = rules_selector.forbidden_enabled
	last_batch_record_path = ""
	replay_last_batch_button.disabled = true
	run_batch_button.disabled = true
	rules_selector.set_disabled(true)
	stats_label.text = "批量进度：0/%d..." % batch_total
	_run_next_batch_game()


func _run_next_batch_game() -> void:
	if batch_done >= batch_total:
		batch_running = false
		run_batch_button.disabled = false
		rules_selector.set_disabled(false)
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


func _apply_phone_layout() -> void:
	if not is_node_ready():
		return
	if not _is_phone_portrait():
		_restore_default_layout()
		return

	var content_width := _phone_content_width()
	lab_container.set_anchors_preset(Control.PRESET_CENTER)
	lab_container.custom_minimum_size = Vector2(content_width, 0.0)
	lab_container.offset_left = -content_width * 0.5
	lab_container.offset_right = content_width * 0.5
	lab_container.offset_top = -350.0
	lab_container.offset_bottom = 350.0
	var compact := get_viewport_rect().size.x < 428.0
	lab_container.add_theme_constant_override("separation", 6 if compact else 10)

	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 26 if compact else 30)
	match_row.vertical = true
	match_row.custom_minimum_size.x = content_width
	match_row.add_theme_constant_override("separation", 6 if compact else 8)
	$VBoxContainer/MatchRow/BlackLabel.visible = false
	$VBoxContainer/MatchRow/WhiteLabel.visible = false
	black_level.custom_minimum_size.x = content_width
	white_level.custom_minimum_size.x = content_width
	black_level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	white_level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_row.custom_minimum_size.x = content_width
	rules_selector.custom_minimum_size.x = content_width
	action_row.vertical = true
	action_row.custom_minimum_size.x = content_width
	action_row.add_theme_constant_override("separation", 6 if compact else 10)
	_apply_phone_button(watch_button, 19)
	_apply_phone_button(run_batch_button, 19)
	_apply_phone_button(replay_last_batch_button, 18)
	_apply_phone_button(back_button, 18)
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_label.add_theme_font_size_override("font_size", 12 if compact else 14)


func _restore_default_layout() -> void:
	lab_container.set_anchors_preset(Control.PRESET_CENTER)
	lab_container.custom_minimum_size = Vector2.ZERO
	lab_container.offset_left = -280.0
	lab_container.offset_top = -320.0
	lab_container.offset_right = 280.0
	lab_container.offset_bottom = 320.0
	lab_container.add_theme_constant_override("separation", 12)
	title_label.add_theme_font_size_override("font_size", 32)
	match_row.vertical = false
	match_row.custom_minimum_size = Vector2.ZERO
	match_row.add_theme_constant_override("separation", 10)
	$VBoxContainer/MatchRow/BlackLabel.visible = true
	$VBoxContainer/MatchRow/WhiteLabel.visible = true
	black_level.custom_minimum_size = Vector2.ZERO
	white_level.custom_minimum_size = Vector2.ZERO
	black_level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	white_level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_row.custom_minimum_size = Vector2.ZERO
	rules_selector.custom_minimum_size.x = 0.0
	action_row.vertical = false
	action_row.custom_minimum_size = Vector2.ZERO
	action_row.add_theme_constant_override("separation", 10)
	watch_button.custom_minimum_size = Vector2(0.0, 44.0)
	watch_button.add_theme_font_size_override("font_size", 16)
	run_batch_button.custom_minimum_size = Vector2(0.0, 44.0)
	run_batch_button.add_theme_font_size_override("font_size", 16)
	replay_last_batch_button.custom_minimum_size = Vector2(0.0, 44.0)
	replay_last_batch_button.add_theme_font_size_override("font_size", 16)
	back_button.custom_minimum_size = Vector2(0.0, 40.0)
	back_button.add_theme_font_size_override("font_size", 16)
	stats_label.add_theme_font_size_override("font_size", 14)


func _is_phone_portrait() -> bool:
	var viewport_size := get_viewport_rect().size
	return viewport_size.y > viewport_size.x and viewport_size.x <= 700.0


func _phone_side_margin(width: float) -> float:
	return clampf(width * 0.04, 14.0, 17.0)


func _phone_content_width() -> float:
	var width := get_viewport_rect().size.x
	return width - _phone_side_margin(width) * 2.0


func _phone_primary_button_height() -> float:
	return 60.0 if get_viewport_rect().size.x >= 428.0 else 48.0


func _apply_phone_button(button: Button, font_size: int = 19) -> void:
	button.custom_minimum_size = Vector2(_phone_content_width(), _phone_primary_button_height())
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var applied_font_size: int = font_size if get_viewport_rect().size.x >= 428.0 else mini(font_size, 16)
	button.add_theme_font_size_override("font_size", applied_font_size)
