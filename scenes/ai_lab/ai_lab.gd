extends Control

const _GameLogic = preload("res://scripts/game_logic.gd")
const _GameRecord = preload("res://scripts/data/game_record.gd")

const LEVEL_NAMES: Array[String] = ["L1 Random", "L2 Heuristic", "L3 Minimax", "L4 Minimax+", "L5 MCTS", "L6 Neural"]
const SPEED_NAMES: Array[String] = ["Instant", "Fast", "Normal", "Slow"]
const SPEED_VALUES: Array[float] = [0.0, 0.1, 0.5, 2.0]

@onready var black_level: OptionButton = %BlackLevel
@onready var white_level: OptionButton = %WhiteLevel
@onready var speed_slider: HSlider = %SpeedSlider
@onready var speed_text: Label = %SpeedText
@onready var stats_label: Label = %StatsLabel

var batch_running: bool = false
var batch_total: int = 0
var batch_done: int = 0
var batch_wins_b: int = 0
var batch_wins_w: int = 0


func _ready() -> void:
	for name in LEVEL_NAMES:
		black_level.add_item(name)
		white_level.add_item(name)
	black_level.selected = 3  # L4 Minimax+
	white_level.selected = 4  # L5 MCTS

	speed_slider.value_changed.connect(_on_speed_changed)
	%WatchButton.pressed.connect(_on_watch_pressed)
	%RunBatchButton.pressed.connect(_on_run_batch_pressed)
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
	GameManager.setup_ai_vs_ai(engine_b, engine_w)
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
	%RunBatchButton.disabled = true
	stats_label.text = "Batch: 0/%d..." % batch_total
	_run_next_batch_game()


func _run_next_batch_game() -> void:
	if batch_done >= batch_total:
		batch_running = false
		%RunBatchButton.disabled = false
		stats_label.text = "Batch done: B=%d W=%d D=%d | Total records: %d" % [
			batch_wins_b, batch_wins_w, batch_total - batch_wins_b - batch_wins_w,
			_GameRecord.list_records().size()]
		return

	# Use black/white level selections so batch mode can compare different levels.
	# (For self-play / weight training, just set both dropdowns to the same level.)
	var engine_b = _create_engine(black_level.selected)
	var engine_w = _create_engine(white_level.selected)

	# Run a headless game using game logic directly
	var logic = _GameLogic.new()
	var current = _GameLogic.BLACK

	while not logic.game_over:
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
	record.result = logic.winner
	record.total_moves = logic.move_history.size()
	for m in logic.move_history:
		record.moves.append([m.x, m.y])
	var path = _GameRecord.get_records_dir() + "/" + record.timestamp + ".json"
	_GameRecord.save_to_file(record, path)

	if logic.winner == _GameLogic.BLACK:
		batch_wins_b += 1
	elif logic.winner == _GameLogic.WHITE:
		batch_wins_w += 1

	batch_done += 1
	stats_label.text = "Batch: %d/%d (B:%d W:%d)" % [batch_done, batch_total, batch_wins_b, batch_wins_w]

	# Use call_deferred to avoid stack overflow and allow UI updates
	_run_next_batch_game.call_deferred()



func _update_stats() -> void:
	var count = _GameRecord.list_records().size()
	stats_label.text = "Records: %d | Ready" % count


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
