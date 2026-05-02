extends Node

func _ready() -> void:
	var selector_scene: PackedScene = load("res://scenes/common/rules_card_selector.tscn")
	assert(selector_scene != null)
	var selector = selector_scene.instantiate()
	add_child(selector)
	await get_tree().process_frame

	assert(selector.forbidden_enabled == true)
	assert(selector.has_signal("selection_changed"))
	assert(selector.get_node("%FreeTitle").text == "自由五子棋")
	assert(selector.get_node("%FreeDescription").text == "双方自由落子")
	assert(selector.get_node("%ForbiddenTitle").text == "禁手规则")
	assert(selector.get_node("%ForbiddenDescription").text == "黑棋禁手不可落子")

	var changed: Array[bool] = []
	selector.selection_changed.connect(func(enabled: bool) -> void:
		changed.append(enabled)
	)
	selector.get_node("%FreeCard").pressed.emit()
	await get_tree().process_frame
	assert(selector.forbidden_enabled == false)
	assert(changed == [false])

	selector.set_disabled(true)
	assert(selector.get_node("%FreeCard").disabled == true)
	assert(selector.get_node("%ForbiddenCard").disabled == true)
	selector.set_disabled(false)
	assert(selector.get_node("%FreeCard").disabled == false)
	assert(selector.get_node("%ForbiddenCard").disabled == false)

	print("RULES_CARD_SELECTOR_TASK1_TESTS PASS")
	get_tree().quit()
