extends Control

@onready var free_button: Button = %FreeButton
@onready var renju_button: Button = %RenjuButton
@onready var start_button: Button = %StartButton

var forbidden_enabled: bool = false


func _ready() -> void:
	free_button.pressed.connect(_on_free_pressed)
	renju_button.pressed.connect(_on_renju_pressed)
	start_button.pressed.connect(_on_start_pressed)
	%BackButton.pressed.connect(_on_back_pressed)
	_update_selection()


func _on_free_pressed() -> void:
	forbidden_enabled = false
	_update_selection()


func _on_renju_pressed() -> void:
	forbidden_enabled = true
	_update_selection()


func _update_selection() -> void:
	free_button.disabled = not forbidden_enabled
	renju_button.disabled = forbidden_enabled


func _on_start_pressed() -> void:
	GameManager.setup_local_pvp(forbidden_enabled)
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
