extends Node

const SMALL_IPHONE_SIZE := Vector2i(375, 812)
const PROMAX_IPHONE_SIZE := Vector2i(430, 932)
const PROMAX_CONTENT_MIN_WIDTH: float = 396.0
const SMALL_CONTENT_MIN_WIDTH: float = 343.0
const PROMAX_PRIMARY_BUTTON_MIN_HEIGHT: float = 56.0
const PROMAX_TITLE_FONT_MIN: int = 28
const PROMAX_BUTTON_FONT_MIN: int = 18

var _failed: bool = false


func _ready() -> void:
	await _run_all()
	if _failed:
		get_tree().quit(1)
	else:
		print("IPHONE_PORTRAIT_MENU_UI_TASK_TESTS PASS")
		get_tree().quit(0)


func _run_all() -> void:
	await _assert_scene_phone_layout("res://scenes/main_menu/main_menu.tscn", ["LocalPvpButton", "VsAiButton", "OnlineButton", "AiLabButton", "QuitButton"], [])
	await _assert_scene_phone_layout("res://scenes/local_setup/local_setup.tscn", ["StartButton", "BackButton"], ["RulesSelector"])
	await _assert_scene_phone_layout("res://scenes/ai_setup/ai_setup.tscn", ["BlackButton", "WhiteButton", "StartButton", "BackButton"], ["LevelGrid", "RulesSelector"])
	await _assert_scene_phone_layout("res://scenes/ai_lab/ai_lab.tscn", ["WatchButton", "RunBatchButton", "ReplayLastBatchButton", "BackButton"], ["RulesSelector"])
	await _assert_small_phone_containment("res://scenes/main_menu/main_menu.tscn")
	await _assert_small_phone_containment("res://scenes/local_setup/local_setup.tscn")
	await _assert_small_phone_containment("res://scenes/ai_setup/ai_setup.tscn")
	await _assert_small_phone_containment("res://scenes/ai_lab/ai_lab.tscn")
	await _assert_horizontal_resize_restoration("res://scenes/main_menu/main_menu.tscn", ["LocalPvpButton", "VsAiButton", "OnlineButton", "AiLabButton", "QuitButton", "HostButton", "JoinButton"], [])
	await _assert_horizontal_resize_restoration("res://scenes/local_setup/local_setup.tscn", ["StartButton", "BackButton"], ["RulesSelector"])
	await _assert_horizontal_resize_restoration("res://scenes/ai_setup/ai_setup.tscn", ["BlackButton", "WhiteButton", "StartButton", "BackButton"], ["LevelGrid", "RulesSelector", "ColorButtons", "BottomButtons"])
	await _assert_ai_setup_horizontal_resize_restoration()
	await _assert_horizontal_resize_restoration("res://scenes/ai_lab/ai_lab.tscn", ["WatchButton", "RunBatchButton", "ReplayLastBatchButton", "BackButton"], ["BlackLevel", "WhiteLevel", "RulesSelector", "ActionRow", "MatchRow"])


func _assert_scene_phone_layout(scene_path: String, primary_button_names: Array[String], wide_control_names: Array[String]) -> void:
	var viewport := SubViewport.new()
	viewport.size = PROMAX_IPHONE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var packed_scene := load(scene_path) as PackedScene
	var scene := packed_scene.instantiate()
	viewport.add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var root_control := scene as Control
	if not _expect(root_control != null, "%s root should be Control" % scene_path):
		viewport.queue_free()
		return

	for button_name in primary_button_names:
		var button := _find_node(scene, button_name) as Button
		if not _expect(button != null, "%s should exist in %s" % [button_name, scene_path]):
			continue
		_assert_min_width(button, PROMAX_CONTENT_MIN_WIDTH, "%s %s" % [scene_path, button_name])
		_assert_min_height(button, PROMAX_PRIMARY_BUTTON_MIN_HEIGHT, "%s %s" % [scene_path, button_name])
		_assert_centered_x(button, float(PROMAX_IPHONE_SIZE.x), 4.0, "%s %s" % [scene_path, button_name])
		_assert_font_size(button, "font_size", PROMAX_BUTTON_FONT_MIN, "%s %s" % [scene_path, button_name])
		_assert_inside_viewport(button, Vector2(PROMAX_IPHONE_SIZE), "%s %s" % [scene_path, button_name])

	for control_name in wide_control_names:
		var control := _find_node(scene, control_name) as Control
		if not _expect(control != null, "%s should exist in %s" % [control_name, scene_path]):
			continue
		_assert_min_width(control, PROMAX_CONTENT_MIN_WIDTH, "%s %s" % [scene_path, control_name])
		_assert_centered_x(control, float(PROMAX_IPHONE_SIZE.x), 4.0, "%s %s" % [scene_path, control_name])
		_assert_inside_viewport(control, Vector2(PROMAX_IPHONE_SIZE), "%s %s" % [scene_path, control_name])

	var title := _find_node(scene, "TitleLabel") as Label
	if title != null:
		_assert_font_size(title, "font_size", PROMAX_TITLE_FONT_MIN, "%s TitleLabel" % scene_path)
		if not _expect(title.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "%s TitleLabel should be centered" % scene_path):
			pass

	viewport.queue_free()


func _assert_small_phone_containment(scene_path: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = SMALL_IPHONE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var packed_scene := load(scene_path) as PackedScene
	var scene := packed_scene.instantiate()
	viewport.add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	_assert_all_visible_controls_inside(scene, Vector2(SMALL_IPHONE_SIZE), scene_path)

	var buttons := _collect_buttons(scene)
	for button in buttons:
		if button.visible and _is_appropriate_small_width_button(button):
			_assert_min_width(button, SMALL_CONTENT_MIN_WIDTH, "%s %s small width" % [scene_path, button.name])
			_assert_inside_viewport(button, Vector2(SMALL_IPHONE_SIZE))

	viewport.queue_free()


func _assert_horizontal_resize_restoration(scene_path: String, button_names: Array[String], control_names: Array[String]) -> void:
	var viewport := SubViewport.new()
	viewport.size = PROMAX_IPHONE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var packed_scene := load(scene_path) as PackedScene
	var scene := packed_scene.instantiate()
	viewport.add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	viewport.size = Vector2i(932, 430)
	await get_tree().process_frame
	await get_tree().process_frame

	for button_name in button_names:
		var button := _find_node(scene, button_name) as Button
		if button != null and button.is_visible_in_tree():
			_assert_max_minimum_width(button, 260.0, "%s %s horizontal restored" % [scene_path, button_name])

	for control_name in control_names:
		var control := _find_node(scene, control_name) as Control
		if control != null and control.is_visible_in_tree():
			_assert_max_minimum_width(control, 360.0, "%s %s horizontal restored" % [scene_path, control_name])

	var action_row := _find_node(scene, "ActionRow") as BoxContainer
	if action_row != null:
		_expect(not action_row.vertical, "%s ActionRow should restore horizontal orientation" % scene_path)
	var match_row := _find_node(scene, "MatchRow") as BoxContainer
	if match_row != null:
		_expect(not match_row.vertical, "%s MatchRow should restore horizontal orientation" % scene_path)

	viewport.queue_free()


func _assert_ai_setup_horizontal_resize_restoration() -> void:
	var viewport := SubViewport.new()
	viewport.size = PROMAX_IPHONE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var scene := preload("res://scenes/ai_setup/ai_setup.tscn").instantiate()
	viewport.add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	viewport.size = Vector2i(932, 430)
	await get_tree().process_frame
	await get_tree().process_frame

	var color_buttons := _find_node(scene, "ColorButtons") as HBoxContainer
	var bottom_buttons := _find_node(scene, "BottomButtons") as HBoxContainer
	var black_button := _find_node(scene, "BlackButton") as Button
	var white_button := _find_node(scene, "WhiteButton") as Button
	var back_button := _find_node(scene, "BackButton") as Button
	var start_button := _find_node(scene, "StartButton") as Button
	var color_stack := _find_node(scene, "PhoneColorButtons") as Control
	var bottom_stack := _find_node(scene, "PhoneBottomButtons") as Control

	_expect(black_button.get_parent() == color_buttons, "AI setup BlackButton should return to ColorButtons after horizontal resize")
	_expect(white_button.get_parent() == color_buttons, "AI setup WhiteButton should return to ColorButtons after horizontal resize")
	_expect(back_button.get_parent() == bottom_buttons, "AI setup BackButton should return to BottomButtons after horizontal resize")
	_expect(start_button.get_parent() == bottom_buttons, "AI setup StartButton should return to BottomButtons after horizontal resize")
	for button: Button in [black_button, white_button, back_button, start_button]:
		_expect(button.size_flags_horizontal == Control.SIZE_FILL, "%s should restore horizontal size flags" % button.name)
	if color_stack != null:
		_expect(not color_stack.visible, "PhoneColorButtons should not remain visible after horizontal resize")
	if bottom_stack != null:
		_expect(not bottom_stack.visible, "PhoneBottomButtons should not remain visible after horizontal resize")

	viewport.queue_free()


func _collect_buttons(node: Node) -> Array[Button]:
	var result: Array[Button] = []
	if node is Button:
		result.append(node)
	for child in node.get_children():
		result.append_array(_collect_buttons(child))
	return result


func _assert_all_visible_controls_inside(node: Node, viewport_size: Vector2, scene_path: String) -> void:
	if node is Control:
		var control := node as Control
		if not control.is_visible_in_tree():
			return
		_assert_inside_viewport(control, viewport_size, "%s %s" % [scene_path, control.name])
	for child in node.get_children():
		_assert_all_visible_controls_inside(child, viewport_size, scene_path)


func _is_appropriate_small_width_button(button: Button) -> bool:
	if not button.is_visible_in_tree():
		return false
	var parent := button.get_parent()
	if parent is GridContainer:
		return false
	var name_text := String(button.name)
	if name_text.begins_with("Level"):
		return false
	return true


func _find_node(root: Node, node_name: String) -> Node:
	if root.name == node_name:
		return root
	for child in root.get_children():
		var found := _find_node(child, node_name)
		if found != null:
			return found
	return null


func _assert_inside_viewport(control: Control, viewport_size: Vector2, message: String = "") -> bool:
	var rect := control.get_global_rect()
	var label: String = message if message != "" else String(control.name)
	return _expect(
		rect.position.x >= -0.5 and rect.position.y >= -0.5 and rect.end.x <= viewport_size.x + 0.5 and rect.end.y <= viewport_size.y + 0.5,
		"%s outside %s: %s" % [label, viewport_size, rect]
	)


func _assert_centered_x(control: Control, viewport_width: float, tolerance: float, message: String) -> bool:
	var rect := control.get_global_rect()
	var center_x := rect.position.x + rect.size.x * 0.5
	return _expect(absf(center_x - viewport_width * 0.5) <= tolerance, "%s center %.1f expected %.1f rect=%s" % [message, center_x, viewport_width * 0.5, rect])


func _assert_min_width(control: Control, min_width: float, message: String) -> bool:
	var rect := control.get_global_rect()
	return _expect(rect.size.x >= min_width, "%s width %.1f expected >= %.1f rect=%s" % [message, rect.size.x, min_width, rect])


func _assert_max_minimum_width(control: Control, max_width: float, message: String) -> bool:
	return _expect(control.custom_minimum_size.x <= max_width, "%s minimum width %.1f expected <= %.1f" % [message, control.custom_minimum_size.x, max_width])


func _assert_min_height(control: Control, min_height: float, message: String) -> bool:
	var rect := control.get_global_rect()
	return _expect(rect.size.y >= min_height, "%s height %.1f expected >= %.1f rect=%s" % [message, rect.size.y, min_height, rect])


func _assert_font_size(control: Control, override_name: String, min_size: int, message: String) -> bool:
	var font_size := control.get_theme_font_size(override_name)
	return _expect(font_size >= min_size, "%s font size %d expected >= %d" % [message, font_size, min_size])


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_failed = true
		push_error(message)
		print("FAIL: %s" % message)
	return condition
