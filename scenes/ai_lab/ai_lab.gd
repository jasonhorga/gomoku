extends Control

const _GameLogic = preload("res://scripts/game_logic.gd")
const _GameRecord = preload("res://scripts/data/game_record.gd")

const LEVEL_NAMES: Array[String] = ["L1 Random ★", "L2 Heuristic ★★", "L3 Minimax ★★★", "L4 Minimax+ ★★★★", "L5 MCTS ★★★★", "L6 Neural ★★★★★"]
const SPEED_NAMES: Array[String] = ["Instant", "Fast", "Normal", "Slow"]
const SPEED_VALUES: Array[float] = [0.0, 0.1, 0.5, 2.0]

# Fixed 3-move openings for benchmark mode. Each opening is [B, W, B];
# AIs play from move 4 onward. With colour alternation, 5 openings × 2
# colours = 10 unique games per batch cycle, breaking MCTS determinism
# without weakening play (each engine still picks argmax-by-visits).
const OPENINGS: Array = [
	[Vector2i(7,7), Vector2i(7,8), Vector2i(8,8)],
	[Vector2i(7,7), Vector2i(7,8), Vector2i(5,7)],
	[Vector2i(7,7), Vector2i(8,8), Vector2i(8,7)],
	[Vector2i(7,7), Vector2i(6,9), Vector2i(8,8)],
	[Vector2i(7,7), Vector2i(5,5), Vector2i(8,7)],
]

@onready var black_level: OptionButton = %BlackLevel
@onready var white_level: OptionButton = %WhiteLevel
@onready var speed_slider: HSlider = %SpeedSlider
@onready var speed_text: Label = %SpeedText
@onready var stats_label: Label = %StatsLabel
@onready var standard_openings_check: CheckButton = %StandardOpenings

var batch_running: bool = false
var batch_total: int = 0
var batch_done: int = 0
var batch_wins_b: int = 0
var batch_wins_w: int = 0
var use_standard_openings: bool = false


func _ready() -> void:
	for name in LEVEL_NAMES:
		black_level.add_item(name)
		white_level.add_item(name)
	black_level.selected = 3  # L4 Minimax+
	white_level.selected = 4  # L5 MCTS

	speed_slider.value_changed.connect(_on_speed_changed)
	standard_openings_check.toggled.connect(func(p): use_standard_openings = p)
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

	# Colour alternation. In default mode, swap every other game. In
	# standard-openings mode, swap once per opening cycle so each opening
	# is played twice (B as engine_b, then B as engine_w) before moving
	# to the next opening.
	var swap_colors: bool = false
	var opening_idx: int = -1
	if use_standard_openings:
		opening_idx = batch_done % OPENINGS.size()
		swap_colors = (batch_done / OPENINGS.size()) % 2 == 1
	else:
		swap_colors = (batch_done % 2 == 1)

	var engine_b
	var engine_w
	if swap_colors:
		engine_b = _create_engine(white_level.selected)
		engine_w = _create_engine(black_level.selected)
	else:
		engine_b = _create_engine(black_level.selected)
		engine_w = _create_engine(white_level.selected)

	# Run a headless game using game logic directly
	var logic = _GameLogic.new()
	var current = _GameLogic.BLACK

	# Inject the fixed opening (3 moves) so MCTS determinism doesn't
	# collapse the batch to 2 unique games. After [B, W, B] it's white's
	# turn — engines take over from move 4.
	if opening_idx >= 0:
		for m in OPENINGS[opening_idx]:
			logic.place_stone(m.x, m.y)
		current = _GameLogic.WHITE

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
	record.result = logic.winner
	record.total_moves = logic.move_history.size()
	for m in logic.move_history:
		record.moves.append([m.x, m.y])
	var path = _GameRecord.get_records_dir() + "/" + record.timestamp + ".json"
	_GameRecord.save_to_file(record, path)

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
	stats_label.text = "Batch: %d/%d (%s:%d %s:%d)" % [
		batch_done, batch_total,
		LEVEL_NAMES[black_level.selected], batch_wins_b,
		LEVEL_NAMES[white_level.selected], batch_wins_w
	]

	# Use call_deferred to avoid stack overflow and allow UI updates
	_run_next_batch_game.call_deferred()



func _update_stats() -> void:
	var count = _GameRecord.list_records().size()
	stats_label.text = "Records: %d | Ready" % count


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
