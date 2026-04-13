extends Control

@onready var waiting_label: Label = %WaitingLabel
@onready var info_label: Label = %InfoLabel
@onready var ip_info_label: Label = %IPInfoLabel
@onready var cancel_button: Button = %CancelButton


func _ready() -> void:
	cancel_button.pressed.connect(_on_cancel_pressed)
	NetworkManager.game_start_ready.connect(_on_game_start)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)

	if NetworkManager.is_host:
		waiting_label.text = "Waiting for opponent..."
		info_label.text = "You are: Black (first move)"
		var ip: String = NetworkManager.get_local_ip()
		ip_info_label.text = "Your IP: %s  Port: %d" % [ip, NetworkManager.PORT]
		ip_info_label.visible = true
	else:
		waiting_label.text = "Connected! Starting game..."
		info_label.text = "You are: White"
		ip_info_label.visible = false


func _on_game_start() -> void:
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")


func _on_cancel_pressed() -> void:
	NetworkManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")


func _on_player_disconnected(_id: int) -> void:
	waiting_label.text = "Opponent disconnected."
	waiting_label.add_theme_color_override("font_color", Color.RED)


func _exit_tree() -> void:
	if NetworkManager.game_start_ready.is_connected(_on_game_start):
		NetworkManager.game_start_ready.disconnect(_on_game_start)
	if NetworkManager.player_disconnected.is_connected(_on_player_disconnected):
		NetworkManager.player_disconnected.disconnect(_on_player_disconnected)
