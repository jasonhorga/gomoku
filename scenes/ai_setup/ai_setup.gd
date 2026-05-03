extends Control

const _GameLogic = preload("res://scripts/game_logic.gd")

var selected_color: int = _GameLogic.BLACK
var selected_level: int = 2
var _color_buttons_original_parent: Node
var _color_buttons_original_indices: Dictionary = {}
var _bottom_buttons_original_parent: Node
var _bottom_buttons_original_indices: Dictionary = {}
var _phone_color_stack: VBoxContainer
var _phone_bottom_stack: VBoxContainer

@onready var setup_container: VBoxContainer = $VBoxContainer
@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var color_label: Label = $VBoxContainer/ColorLabel
@onready var color_buttons: HBoxContainer = $VBoxContainer/ColorButtons
@onready var black_btn: Button = %BlackButton
@onready var white_btn: Button = %WhiteButton
@onready var diff_label: Label = $VBoxContainer/DiffLabel
@onready var level_grid: GridContainer = %LevelGrid
@onready var rules_selector: Control = %RulesSelector
@onready var bottom_buttons: HBoxContainer = %BottomButtons
@onready var back_button: Button = %BackButton
@onready var start_button: Button = %StartButton
@onready var level_btns: Array[Button] = []


func _ready() -> void:
	level_btns = [%Level1, %Level2, %Level3, %Level4, %Level5, %Level6]
	_color_buttons_original_parent = color_buttons
	_color_buttons_original_indices[black_btn] = black_btn.get_index()
	_color_buttons_original_indices[white_btn] = white_btn.get_index()
	_bottom_buttons_original_parent = bottom_buttons
	_bottom_buttons_original_indices[back_button] = back_button.get_index()
	_bottom_buttons_original_indices[start_button] = start_button.get_index()

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

	back_button.pressed.connect(_on_back)
	start_button.pressed.connect(_on_start)
	get_viewport().size_changed.connect(_apply_phone_layout)

	_update_ui()
	_apply_phone_layout()


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
	GameManager.setup_vs_ai(selected_color, engine, rules_selector.forbidden_enabled)
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")


func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")


func _apply_phone_layout() -> void:
	if not is_node_ready():
		return
	if not _is_phone_portrait():
		_restore_default_layout()
		return

	var content_width := _phone_content_width()
	setup_container.set_anchors_preset(Control.PRESET_CENTER)
	setup_container.custom_minimum_size = Vector2(content_width, 0.0)
	setup_container.offset_left = -content_width * 0.5
	setup_container.offset_right = content_width * 0.5
	setup_container.offset_top = -330.0
	setup_container.offset_bottom = 330.0
	var compact := get_viewport_rect().size.x < 428.0
	setup_container.add_theme_constant_override("separation", 6 if compact else 10)

	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 26 if compact else 30)
	color_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	color_label.add_theme_font_size_override("font_size", 14 if compact else 17)
	diff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	diff_label.add_theme_font_size_override("font_size", 14 if compact else 17)
	_ensure_ai_setup_phone_button_hosts()
	color_buttons.custom_minimum_size.x = content_width
	color_buttons.add_theme_constant_override("separation", 6 if compact else 10)
	_apply_phone_button(black_btn, 18)
	_apply_phone_button(white_btn, 18)
	level_grid.custom_minimum_size.x = content_width
	level_grid.columns = 2
	level_grid.add_theme_constant_override("h_separation", 10)
	level_grid.add_theme_constant_override("v_separation", 4 if compact else 8)
	for button in level_btns:
		button.custom_minimum_size = Vector2((content_width - 10.0) * 0.5, 38.0 if compact else 44.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 16)
	rules_selector.custom_minimum_size.x = content_width
	bottom_buttons.custom_minimum_size.x = content_width
	bottom_buttons.add_theme_constant_override("separation", 6 if compact else 10)
	_apply_phone_button(back_button, 19)
	_apply_phone_button(start_button, 20)


func _ensure_ai_setup_phone_button_hosts() -> void:
	if _phone_color_stack == null:
		_phone_color_stack = VBoxContainer.new()
		_phone_color_stack.name = "PhoneColorButtons"
		_phone_color_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		color_buttons.add_child(_phone_color_stack)
	_phone_color_stack.visible = true
	if black_btn.get_parent() != _phone_color_stack:
		black_btn.reparent(_phone_color_stack)
	if white_btn.get_parent() != _phone_color_stack:
		white_btn.reparent(_phone_color_stack)
	_phone_color_stack.custom_minimum_size.x = _phone_content_width()
	_phone_color_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_phone_color_stack.add_theme_constant_override("separation", 6 if get_viewport_rect().size.x < 428.0 else 10)

	if _phone_bottom_stack == null:
		_phone_bottom_stack = VBoxContainer.new()
		_phone_bottom_stack.name = "PhoneBottomButtons"
		_phone_bottom_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bottom_buttons.add_child(_phone_bottom_stack)
	_phone_bottom_stack.visible = true
	if back_button.get_parent() != _phone_bottom_stack:
		back_button.reparent(_phone_bottom_stack)
	if start_button.get_parent() != _phone_bottom_stack:
		start_button.reparent(_phone_bottom_stack)
	_phone_bottom_stack.custom_minimum_size.x = _phone_content_width()
	_phone_bottom_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_phone_bottom_stack.add_theme_constant_override("separation", 6 if get_viewport_rect().size.x < 428.0 else 10)


func _restore_ai_setup_button_hosts() -> void:
	for button: Button in [black_btn, white_btn]:
		if button.get_parent() != _color_buttons_original_parent:
			button.reparent(_color_buttons_original_parent)
			_color_buttons_original_parent.move_child(button, _color_buttons_original_indices[button])
	for button: Button in [back_button, start_button]:
		if button.get_parent() != _bottom_buttons_original_parent:
			button.reparent(_bottom_buttons_original_parent)
			_bottom_buttons_original_parent.move_child(button, _bottom_buttons_original_indices[button])
	if _phone_color_stack != null:
		_phone_color_stack.visible = false
		_phone_color_stack.custom_minimum_size = Vector2.ZERO
		_phone_color_stack.size_flags_horizontal = Control.SIZE_FILL
		_phone_color_stack.remove_theme_constant_override("separation")
	if _phone_bottom_stack != null:
		_phone_bottom_stack.visible = false
		_phone_bottom_stack.custom_minimum_size = Vector2.ZERO
		_phone_bottom_stack.size_flags_horizontal = Control.SIZE_FILL
		_phone_bottom_stack.remove_theme_constant_override("separation")


func _restore_default_layout() -> void:
	_restore_ai_setup_button_hosts()
	setup_container.set_anchors_preset(Control.PRESET_CENTER)
	setup_container.custom_minimum_size = Vector2.ZERO
	setup_container.offset_left = -220.0
	setup_container.offset_top = -300.0
	setup_container.offset_right = 220.0
	setup_container.offset_bottom = 300.0
	setup_container.add_theme_constant_override("separation", 10)
	title_label.add_theme_font_size_override("font_size", 36)
	color_label.add_theme_font_size_override("font_size", 18)
	diff_label.add_theme_font_size_override("font_size", 18)
	color_buttons.custom_minimum_size = Vector2.ZERO
	color_buttons.add_theme_constant_override("separation", 20)
	black_btn.custom_minimum_size = Vector2(150.0, 45.0)
	black_btn.size_flags_horizontal = Control.SIZE_FILL
	black_btn.add_theme_font_size_override("font_size", 18)
	white_btn.custom_minimum_size = Vector2(150.0, 45.0)
	white_btn.size_flags_horizontal = Control.SIZE_FILL
	white_btn.add_theme_font_size_override("font_size", 18)
	level_grid.custom_minimum_size = Vector2.ZERO
	level_grid.columns = 2
	level_grid.add_theme_constant_override("h_separation", 12)
	level_grid.add_theme_constant_override("v_separation", 8)
	for button in level_btns:
		button.custom_minimum_size = Vector2(0.0, 44.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 16)
	rules_selector.custom_minimum_size.x = 0.0
	bottom_buttons.custom_minimum_size = Vector2.ZERO
	bottom_buttons.add_theme_constant_override("separation", 20)
	back_button.custom_minimum_size = Vector2(150.0, 45.0)
	back_button.size_flags_horizontal = Control.SIZE_FILL
	back_button.add_theme_font_size_override("font_size", 18)
	start_button.custom_minimum_size = Vector2(150.0, 45.0)
	start_button.size_flags_horizontal = Control.SIZE_FILL
	start_button.add_theme_font_size_override("font_size", 18)


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
