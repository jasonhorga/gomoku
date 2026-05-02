extends Node

func _ready() -> void:
	var game_script = load("res://scenes/game/game.gd")
	var game = game_script.new()
	assert(game._should_use_vertical_layout(Vector2i(390, 844)) == true)
	assert(game._should_use_vertical_layout(Vector2i(844, 390)) == false)
	assert(game._should_use_vertical_layout(Vector2i(1024, 768)) == false)
	assert(game._should_use_vertical_layout(Vector2i(768, 1024)) == false)

	print("GAME_LAYOUT_TASK4_TESTS PASS")
	get_tree().quit()
