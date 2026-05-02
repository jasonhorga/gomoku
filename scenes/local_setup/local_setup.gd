extends Control

@onready var rules_selector = %RulesSelector
@onready var start_button: Button = %StartButton


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	%BackButton.pressed.connect(_on_back_pressed)


func _on_start_pressed() -> void:
	GameManager.setup_local_pvp(rules_selector.forbidden_enabled)
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
