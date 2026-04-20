extends Control

const _GameLogic = preload("res://scripts/game_logic.gd")

var selected_color: int = _GameLogic.BLACK
var selected_level: int = 2

@onready var black_btn: Button = %BlackButton
@onready var white_btn: Button = %WhiteButton
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

	# L6 on iOS now runs through the GomokuNeural plugin (CoreML-backed
	# hybrid MCTS, same architecture as Mac Python onnx_server). The
	# hide-on-mobile rule only applies if the native plugin isn't there.
	if (OS.has_feature("mobile") or OS.get_name() == "iOS") \
			and not Engine.has_singleton("GomokuNeural"):
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
	black_btn.text = ">> Black" if selected_color == _GameLogic.BLACK else "Black"
	white_btn.text = ">> White" if selected_color == _GameLogic.WHITE else "White"

	var level_names: Array[String] = ["Level 1 - Random", "Level 2 - Heuristic", "Level 3 - Minimax", "Level 4 - Minimax+", "Level 5 - MCTS", "Level 6 - Neural Net"]
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
			# iPhone memory is tight; 3000 sims allocates a very large tree
			# every move. Drop to 1500 on mobile — still strong, and survives
			# 50+ move games without OOM.
			var mobile := OS.has_feature("mobile") or OS.get_name() == "iOS"
			return load("res://scripts/ai/ai_mcts.gd").new(1500 if mobile else 3000)
		6:
			return load("res://scripts/ai/ai_neural.gd").new()
		_:
			return load("res://scripts/ai/ai_random.gd").new()


func _on_start() -> void:
	var engine = _create_engine()
	GameManager.setup_vs_ai(selected_color, engine)
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")


func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
