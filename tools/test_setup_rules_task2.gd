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
	var level6: Button = ai_setup.get_node("%Level6")
	level6.visible = true
	await get_tree().process_frame
	assert(ai_setup.get_node("%RulesSelector").forbidden_enabled == true)
	assert(ai_setup.has_node("%RenjuCheckBox") == false)
	assert(ai_setup.has_node("%LevelGrid"))
	var level_grid: GridContainer = ai_setup.get_node("%LevelGrid")
	assert(level_grid.columns == 2)
	assert(ai_setup.has_node("%RulesSelector"))
	assert(ai_setup.has_node("%BottomButtons"))
	var main_vbox: VBoxContainer = ai_setup.get_node("VBoxContainer")
	assert(main_vbox.offset_bottom - main_vbox.offset_top >= 560.0)
	var bottom_buttons: HBoxContainer = ai_setup.get_node("%BottomButtons")
	var root_height: float = ai_setup.size.y
	if root_height > 0.0 and bottom_buttons.size.y > 0.0:
		assert(bottom_buttons.global_position.y + bottom_buttons.size.y <= root_height)

	print("SETUP_RULES_TASK2_TESTS PASS")
	get_tree().quit()
