extends Node

func _ready() -> void:
	var lab_scene: PackedScene = load("res://scenes/ai_lab/ai_lab.tscn")
	assert(lab_scene != null)
	var lab = lab_scene.instantiate()
	get_tree().root.add_child.call_deferred(lab)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(lab.get_node("%RulesSelector").forbidden_enabled == true)
	assert(lab.has_node("%RenjuCheckBox") == false)
	lab.queue_free()

	var game_script = load("res://scenes/game/game.gd")
	var game = game_script.new()
	GameManager.forbidden_enabled = true
	assert(game._ruleset_suffix() == "（禁手规则）")
	GameManager.forbidden_enabled = false
	assert(game._ruleset_suffix() == "（自由五子棋）")
	game.free()
	await get_tree().process_frame

	print("AI_LAB_RULES_TASK3_TESTS PASS")
	get_tree().quit()
