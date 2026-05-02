extends Node

func _ready() -> void:
	var selector_scene: PackedScene = load("res://scenes/common/rules_card_selector.tscn")
	assert(selector_scene != null)
	var selector = selector_scene.instantiate()
	add_child(selector)
	await get_tree().process_frame

	var free_card: Button = selector.get_node("%FreeCard")
	var forbidden_card: Button = selector.get_node("%ForbiddenCard")
	var free_title: Label = selector.get_node("%FreeTitle")
	var forbidden_title: Label = selector.get_node("%ForbiddenTitle")

	assert(selector.forbidden_enabled == true)
	assert(selector.has_signal("selection_changed"))
	assert(free_card.text == "")
	assert(forbidden_card.text == "")
	assert(free_title.text == "自由五子棋")
	assert(selector.get_node("%FreeDescription").text == "双方自由落子")
	assert(forbidden_title.text == "✓ 禁手规则")
	assert(selector.get_node("%ForbiddenDescription").text == "黑棋禁手不可落子")

	var changed: Array[bool] = []
	selector.selection_changed.connect(func(enabled: bool) -> void:
		changed.append(enabled)
	)
	free_card.pressed.emit()
	await get_tree().process_frame
	assert(selector.forbidden_enabled == false)
	assert(changed == [false])
	assert(free_title.text == "✓ 自由五子棋")
	assert(forbidden_title.text == "禁手规则")

	selector.forbidden_enabled = true
	await get_tree().process_frame
	assert(selector.forbidden_enabled == true)
	assert(changed == [false])
	assert(free_title.text == "自由五子棋")
	assert(forbidden_title.text == "✓ 禁手规则")

	selector.set_disabled(true)
	assert(free_card.disabled == true)
	assert(forbidden_card.disabled == true)
	selector.set_disabled(false)
	assert(free_card.disabled == false)
	assert(forbidden_card.disabled == false)

	print("RULES_CARD_SELECTOR_TASK1_TESTS PASS")
	get_tree().quit()
