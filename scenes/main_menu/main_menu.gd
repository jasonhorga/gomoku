extends Control

@onready var ip_input: LineEdit = %IPInput
@onready var status_label: Label = %StatusLabel
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var online_panel: VBoxContainer = %OnlinePanel


func _ready() -> void:
	NetworkManager.connection_failed.connect(_on_connection_failed)
	%LocalPvpButton.pressed.connect(_on_local_pvp_pressed)
	%VsAiButton.pressed.connect(_on_vs_ai_pressed)
	%OnlineButton.pressed.connect(_on_online_pressed)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	%AiLabButton.pressed.connect(_on_ai_lab_pressed)
	%QuitButton.pressed.connect(_on_quit_pressed)
	# iOS apps can't quit programmatically (Apple HIG); hide the button
	# so users aren't confused by a non-functional control.
	if OS.has_feature("mobile") or OS.get_name() == "iOS":
		%QuitButton.visible = false


func _on_local_pvp_pressed() -> void:
	GameManager.setup_local_pvp()
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")


func _on_vs_ai_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ai_setup/ai_setup.tscn")


func _on_online_pressed() -> void:
	online_panel.visible = not online_panel.visible


func _on_host_pressed() -> void:
	if NetworkManager.host_game():
		GameManager.setup_online(NetworkManager.my_player_color)
		get_tree().change_scene_to_file("res://scenes/lobby/lobby.tscn")
	else:
		status_label.text = "Failed to create server. Port may be in use."
		status_label.add_theme_color_override("font_color", Color.RED)


func _on_join_pressed() -> void:
	var ip: String = ip_input.text.strip_edges()
	if ip.is_empty():
		status_label.text = "Please enter an IP address."
		status_label.add_theme_color_override("font_color", Color.RED)
		return
	if NetworkManager.join_game(ip):
		GameManager.setup_online(NetworkManager.my_player_color)
		status_label.text = "Connecting..."
		status_label.add_theme_color_override("font_color", Color.YELLOW)
		host_button.disabled = true
		join_button.disabled = true
		NetworkManager.game_start_ready.connect(_on_game_start, CONNECT_ONE_SHOT)
	else:
		status_label.text = "Failed to connect."
		status_label.add_theme_color_override("font_color", Color.RED)


func _on_game_start() -> void:
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")


func _on_ai_lab_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ai_lab/ai_lab.tscn")


func _on_connection_failed() -> void:
	status_label.text = "Connection failed. Check the IP and try again."
	status_label.add_theme_color_override("font_color", Color.RED)
	host_button.disabled = false
	join_button.disabled = false


func _on_quit_pressed() -> void:
	get_tree().quit()


func _exit_tree() -> void:
	if NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.disconnect(_on_connection_failed)
