extends Control

@onready var setup_container: VBoxContainer = $VBoxContainer
@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var rules_selector: Control = %RulesSelector
@onready var start_button: Button = %StartButton
@onready var back_button: Button = %BackButton


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)
	get_viewport().size_changed.connect(_apply_phone_layout)
	_apply_phone_layout()


func _on_start_pressed() -> void:
	GameManager.setup_local_pvp(rules_selector.forbidden_enabled)
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")


func _on_back_pressed() -> void:
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
	setup_container.offset_top = -260.0
	setup_container.offset_bottom = 260.0
	setup_container.add_theme_constant_override("separation", 12)

	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 30)
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_font_size_override("font_size", 16)
	rules_selector.custom_minimum_size.x = content_width
	_apply_phone_button(start_button, 20)
	_apply_phone_button(back_button, 19)


func _restore_default_layout() -> void:
	setup_container.set_anchors_preset(Control.PRESET_CENTER)
	setup_container.custom_minimum_size = Vector2.ZERO
	setup_container.offset_left = -220.0
	setup_container.offset_top = -210.0
	setup_container.offset_right = 220.0
	setup_container.offset_bottom = 210.0
	setup_container.add_theme_constant_override("separation", 14)
	title_label.add_theme_font_size_override("font_size", 36)
	subtitle_label.add_theme_font_size_override("font_size", 16)
	rules_selector.custom_minimum_size.x = 0.0
	start_button.custom_minimum_size = Vector2(0.0, 52.0)
	start_button.add_theme_font_size_override("font_size", 18)
	back_button.custom_minimum_size = Vector2(0.0, 52.0)
	back_button.add_theme_font_size_override("font_size", 18)


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
