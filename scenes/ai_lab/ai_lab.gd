extends Control

const _GameLogic = preload("res://scripts/game_logic.gd")
const _GameRecord = preload("res://scripts/data/game_record.gd")
const _WeightTuner = preload("res://scripts/data/weight_tuner.gd")
const _PatternEval = preload("res://scripts/ai/pattern_evaluator.gd")

const LEVEL_NAMES: Array[String] = ["L1 Random", "L2 Heuristic", "L3 Minimax", "L4 Minimax+", "L5 MCTS"]
const SPEED_NAMES: Array[String] = ["Instant", "Fast", "Normal", "Slow"]
const SPEED_VALUES: Array[float] = [0.0, 0.1, 0.5, 2.0]

@onready var black_level: OptionButton = %BlackLevel
@onready var white_level: OptionButton = %WhiteLevel
@onready var speed_slider: HSlider = %SpeedSlider
@onready var speed_text: Label = %SpeedText
@onready var stats_label: Label = %StatsLabel
@onready var train_level: OptionButton = %TrainLevel

var batch_running: bool = false
var batch_total: int = 0
var batch_done: int = 0
var batch_wins_b: int = 0
var batch_wins_w: int = 0


func _ready() -> void:
	for name in LEVEL_NAMES:
		black_level.add_item(name)
		white_level.add_item(name)
		train_level.add_item(name)
	black_level.selected = 2  # L3
	white_level.selected = 2
	train_level.selected = 2

	speed_slider.value_changed.connect(_on_speed_changed)
	%WatchButton.pressed.connect(_on_watch_pressed)
	%RunBatchButton.pressed.connect(_on_run_batch_pressed)
	%TuneButton.pressed.connect(_on_tune_pressed)
	%ResetWeightsButton.pressed.connect(_on_reset_weights_pressed)
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
		4: return load("res://scripts/ai/ai_mcts.gd").new(1000)
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

	var engine_b = _create_engine(train_level.selected)
	var engine_w = _create_engine(train_level.selected)

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


func _on_tune_pressed() -> void:
	var records_paths = _GameRecord.list_records()
	if records_paths.is_empty():
		stats_label.text = "No records to tune from!"
		return

	var records: Array = []
	for path in records_paths:
		var r = _GameRecord.load_from_file(path)
		if r != null:
			records.append(r)

	if records.is_empty():
		stats_label.text = "Failed to load records!"
		return

	var eval = _PatternEval.new()
	# Try to load existing weights
	eval.load_weights("user://ai_weights/pattern_weights.json")
	var old_weights = eval.weights.duplicate()

	var tuner = _WeightTuner.new()
	var new_weights = tuner.tune_from_records(records, old_weights)

	# Save new weights
	DirAccess.make_dir_recursive_absolute("user://ai_weights")
	eval.weights = new_weights
	eval.save_weights("user://ai_weights/pattern_weights.json")

	# Display changes
	var changes: String = "Tuned: "
	for key in new_weights:
		var diff: float = new_weights[key] - old_weights[key]
		if absf(diff) > 0.01:
			changes += "%s:%+.0f " % [key, diff]
	stats_label.text = changes


func _on_reset_weights_pressed() -> void:
	var eval = _PatternEval.new()
	DirAccess.make_dir_recursive_absolute("user://ai_weights")
	eval.save_weights("user://ai_weights/pattern_weights.json")
	stats_label.text = "Weights reset to defaults"


func _update_stats() -> void:
	var count = _GameRecord.list_records().size()
	stats_label.text = "Records: %d | Ready" % count


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
