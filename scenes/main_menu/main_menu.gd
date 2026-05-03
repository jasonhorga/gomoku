extends Control

@onready var menu_container: VBoxContainer = $VBoxContainer
@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var local_pvp_button: Button = %LocalPvpButton
@onready var vs_ai_button: Button = %VsAiButton
@onready var online_button: Button = %OnlineButton
@onready var ai_lab_button: Button = %AiLabButton
@onready var quit_button: Button = %QuitButton
@onready var ip_input: LineEdit = %IPInput
@onready var status_label: Label = %StatusLabel
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var online_panel: VBoxContainer = %OnlinePanel


func _ready() -> void:
	NetworkManager.connection_failed.connect(_on_connection_failed)
	local_pvp_button.pressed.connect(_on_local_pvp_pressed)
	vs_ai_button.pressed.connect(_on_vs_ai_pressed)
	online_button.pressed.connect(_on_online_pressed)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	ai_lab_button.pressed.connect(_on_ai_lab_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	# iOS apps can't quit programmatically (Apple HIG); hide the button
	# so users aren't confused by a non-functional control.
	if OS.has_feature("mobile") or OS.get_name() == "iOS":
		quit_button.visible = false
	get_viewport().size_changed.connect(_apply_phone_layout)
	_apply_phone_layout()


func _on_local_pvp_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/local_setup/local_setup.tscn")


func _on_vs_ai_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ai_setup/ai_setup.tscn")


func _on_online_pressed() -> void:
	online_panel.visible = not online_panel.visible


func _on_host_pressed() -> void:
	if NetworkManager.host_game():
		GameManager.setup_online(NetworkManager.my_player_color)
		get_tree().change_scene_to_file("res://scenes/lobby/lobby.tscn")
	else:
		status_label.text = "服务器创建失败，端口可能被占用"
		status_label.add_theme_color_override("font_color", Color.RED)


func _on_join_pressed() -> void:
	var ip: String = ip_input.text.strip_edges()
	if ip.is_empty():
		status_label.text = "请输入 IP 地址"
		status_label.add_theme_color_override("font_color", Color.RED)
		return
	if NetworkManager.join_game(ip):
		GameManager.setup_online(NetworkManager.my_player_color)
		status_label.text = "连接中..."
		status_label.add_theme_color_override("font_color", Color.YELLOW)
		host_button.disabled = true
		join_button.disabled = true
		NetworkManager.game_start_ready.connect(_on_game_start, CONNECT_ONE_SHOT)
	else:
		status_label.text = "连接失败"
		status_label.add_theme_color_override("font_color", Color.RED)


func _on_game_start() -> void:
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")


func _on_ai_lab_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ai_lab/ai_lab.tscn")


func _on_connection_failed() -> void:
	status_label.text = "连接失败，请检查 IP 后重试"
	status_label.add_theme_color_override("font_color", Color.RED)
	host_button.disabled = false
	join_button.disabled = false


func _on_quit_pressed() -> void:
	get_tree().quit()


func _exit_tree() -> void:
	if NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.disconnect(_on_connection_failed)


func _apply_phone_layout() -> void:
	if not is_node_ready():
		return
	if not _is_phone_portrait():
		_restore_default_layout()
		return

	var content_width := _phone_content_width()
	menu_container.set_anchors_preset(Control.PRESET_CENTER)
	menu_container.custom_minimum_size = Vector2(content_width, 0.0)
	menu_container.offset_left = -content_width * 0.5
	menu_container.offset_right = content_width * 0.5
	menu_container.offset_top = -250.0
	menu_container.offset_bottom = 250.0
	menu_container.add_theme_constant_override("separation", 12)

	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 42)
	for button: Button in [local_pvp_button, vs_ai_button, online_button, ai_lab_button, quit_button]:
		_apply_phone_button(button, 20)
	_apply_phone_button(host_button, 18)
	join_button.custom_minimum_size = Vector2(96.0, _phone_primary_button_height())
	join_button.add_theme_font_size_override("font_size", 18)
	ip_input.custom_minimum_size = Vector2(0.0, _phone_primary_button_height())
	ip_input.add_theme_font_size_override("font_size", 16)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 16)


func _restore_default_layout() -> void:
	menu_container.set_anchors_preset(Control.PRESET_CENTER)
	menu_container.custom_minimum_size = Vector2.ZERO
	menu_container.offset_left = -200.0
	menu_container.offset_top = -230.0
	menu_container.offset_right = 200.0
	menu_container.offset_bottom = 230.0
	menu_container.add_theme_constant_override("separation", 15)
	title_label.add_theme_font_size_override("font_size", 48)
	for button: Button in [local_pvp_button, vs_ai_button, online_button, ai_lab_button, quit_button]:
		button.custom_minimum_size = Vector2(0.0, 45.0)
		button.add_theme_font_size_override("font_size", 18)
	host_button.custom_minimum_size = Vector2(0.0, 40.0)
	host_button.add_theme_font_size_override("font_size", 16)
	join_button.custom_minimum_size = Vector2(100.0, 40.0)
	join_button.add_theme_font_size_override("font_size", 16)
	ip_input.custom_minimum_size = Vector2(0.0, 40.0)
	ip_input.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_font_size_override("font_size", 14)


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
