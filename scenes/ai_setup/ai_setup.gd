extends Control

const _GameLogic = preload("res://scripts/game_logic.gd")

var selected_color: int = _GameLogic.BLACK
var selected_level: int = 2

@onready var black_btn: Button = %BlackButton
@onready var white_btn: Button = %WhiteButton
@onready var renju_checkbox: CheckBox = %RenjuCheckBox
@onready var level_btns: Array[Button] = []


func _ready() -> void:
	level_btns = [%Level1, %Level2, %Level3, %Level4, %Level5, %Level6]

	black_btn.pressed.connect(_select_color.bind(_GameLogic.BLACK))
	white_btn.pressed.connect(_select_color.bind(_GameLogic.WHITE))

	%Level1.pressed.connect(_select_level.bind(1))
	%Level2.pressed.connect(_select_level.bind(2))
	%Level3.pressed.connect(_select_level.bind(3))
	%Level4.pressed.connect(_select_level.bind(4))
	%Level5.pressed.connect(_select_level.bind(5))
	%Level6.pressed.connect(_select_level.bind(6))

	# L6 runs through the GomokuNeural plugin (CoreML-backed hybrid MCTS
	# on both iOS and macOS after the 2026-04-21 unification). Hide only
	# on platforms where the plugin isn't available (e.g. Linux editor).
	if not Engine.has_singleton("GomokuNeural"):
		%Level6.visible = false
		if selected_level == 6:
			selected_level = 5

	%BackButton.pressed.connect(_on_back)
	%StartButton.pressed.connect(_on_start)

	_update_ui()


func _select_color(c: int) -> void:
	selected_color = c
	_update_ui()


func _select_level(l: int) -> void:
	selected_level = l
	_update_ui()


func _update_ui() -> void:
	black_btn.text = ">> 黑棋" if selected_color == _GameLogic.BLACK else "黑棋"
	white_btn.text = ">> 白棋" if selected_color == _GameLogic.WHITE else "白棋"

	var level_names: Array[String] = ["L1 随机 ★", "L2 启发 ★★", "L3 搜索 ★★★", "L4 强搜索 ★★★★", "L5 蒙特卡洛 ★★★★", "L6 神经网络 ★★★★★"]
	for i in range(level_btns.size()):
		var prefix: String = ">> " if selected_level == (i + 1) else ""
		level_btns[i].text = prefix + level_names[i]


func _create_engine():
	match selected_level:
		1:
			return load("res://scripts/ai/ai_random.gd").new()
		2:
			return load("res://scripts/ai/ai_heuristic.gd").new()
		3:
			return load("res://scripts/ai/ai_minimax.gd").new(2)
		4:
			return load("res://scripts/ai/ai_minimax.gd").new(4)
		5:
			# L5 = pattern-MCTS via Swift plugin (iOS + macOS). Platforms
			# without the plugin (e.g. Linux editor) fall through to L4
			# since we no longer maintain a GDScript MCTS.
			if Engine.has_singleton("GomokuNeural"):
				return load("res://scripts/ai/ai_plugin_wrapper.gd").new(5)
			return load("res://scripts/ai/ai_minimax.gd").new(4)
		6:
			return load("res://scripts/ai/ai_neural.gd").new()
		_:
			return load("res://scripts/ai/ai_random.gd").new()


func _on_start() -> void:
	var engine = _create_engine()
	GameManager.setup_vs_ai(selected_color, engine, renju_checkbox.button_pressed)
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")


func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
