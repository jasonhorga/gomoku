extends Node

func _ready() -> void:
	var local_scene: PackedScene = load("res://scenes/local_setup/local_setup.tscn")
	assert(local_scene != null)
	var local_setup = local_scene.instantiate()
	add_child(local_setup)
	await get_tree().process_frame
	assert(local_setup.get_node("%RulesSelector").forbidden_enabled == true)
	assert(local_setup.get_node("%TitleLabel").text == "本地双人")
	assert(local_setup.get_node("%SubtitleLabel").text == "选择规则后开始对局")

	var ai_scene: PackedScene = load("res://scenes/ai_setup/ai_setup.tscn")
	assert(ai_scene != null)
	var ai_setup = ai_scene.instantiate()
	add_child(ai_setup)
	await get_tree().process_frame
	assert(ai_setup.get_node("%RulesSelector").forbidden_enabled == true)
	assert(ai_setup.has_node("%RenjuCheckBox") == false)

	print("SETUP_RULES_TASK2_TESTS PASS")
	get_tree().quit()
