extends Node

func _find_node(root: Node, target_name: String) -> Node:
	if root.name == target_name:
		return root
	for child in root.get_children():
		var found := _find_node(child, target_name)
		if found != null:
			return found
	return null


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	get_tree().quit(1)
	return false


func _assert_inside_viewport(control: Control, viewport_size: Vector2) -> bool:
	var rect := control.get_global_rect()
	return _expect(
		rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= viewport_size.x and rect.end.y <= viewport_size.y,
		"%s outside %s: %s" % [control.name, viewport_size, rect]
	)


func _ready() -> void:
	await get_tree().process_frame
	GameManager.setup_local_pvp(true)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(390, 844)
	viewport.disable_3d = true
	get_tree().root.add_child(viewport)
	var scene: PackedScene = load("res://scenes/game/game.tscn")
	assert(scene != null)
	var game = scene.instantiate()
	viewport.add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var vertical_layout := _find_node(game, "VerticalLayout") as VBoxContainer
	var horizontal_layout := _find_node(game, "HorizontalLayout") as HBoxContainer
	var turn_label := _find_node(game, "TurnLabel") as Label
	var color_label := _find_node(game, "ColorLabel") as Label
	var move_label := _find_node(game, "MoveLabel") as Label
	var message_label := _find_node(game, "MessageLabel") as Label
	var undo_button := _find_node(game, "UndoButton") as Button
	var new_game_button := _find_node(game, "NewGameButton") as Button
	var back_to_menu_button := _find_node(game, "BackToMenuButton") as Button
	var status_container := _find_node(game, "StatusContainer") as VBoxContainer
	var actions_container := _find_node(game, "ActionsContainer") as VBoxContainer
	var board_frame := _find_node(game, "BoardFrame") as Control

	if not _expect(vertical_layout.visible == true, "VerticalLayout should be visible"):
		return
	if not _expect(horizontal_layout.visible == false, "HorizontalLayout should be hidden"):
		return
	if not _expect(turn_label.get_theme_font_size("font_size") >= 30, "TurnLabel font is too small"):
		return
	if not _expect(color_label.get_theme_font_size("font_size") >= 22, "ColorLabel font is too small"):
		return
	if not _expect(move_label.get_theme_font_size("font_size") >= 20, "MoveLabel font is too small"):
		return
	if not _expect(message_label.get_theme_font_size("font_size") >= 20, "MessageLabel font is too small"):
		return
	if not _expect(undo_button.custom_minimum_size.y >= 64.0, "UndoButton minimum height is too small"):
		return
	if not _expect(new_game_button.custom_minimum_size.y >= 64.0, "NewGameButton minimum height is too small"):
		return
	if not _expect(back_to_menu_button.custom_minimum_size.y >= 64.0, "BackToMenuButton minimum height is too small"):
		return
	if not _expect(vertical_layout.get_theme_constant("separation") >= 12, "VerticalLayout separation is too small"):
		return
	if not _expect(status_container.get_theme_constant("separation") <= 8, "StatusContainer separation is too large"):
		return
	if not _expect(actions_container.get_theme_constant("separation") >= 12, "ActionsContainer separation is too small"):
		return
	if not _expect(undo_button.size.y >= 64.0, "UndoButton rendered height is too small"):
		return
	if not _expect(new_game_button.size.y >= 64.0, "NewGameButton rendered height is too small"):
		return
	if not _expect(back_to_menu_button.size.y >= 64.0, "BackToMenuButton rendered height is too small"):
		return
	if not _expect(status_container.get_global_rect().intersects(actions_container.get_global_rect()) == false, "StatusContainer overlaps ActionsContainer"):
		return
	if not _assert_inside_viewport(vertical_layout, Vector2(viewport.size)):
		return
	if not _assert_inside_viewport(turn_label, Vector2(viewport.size)):
		return
	if not _assert_inside_viewport(message_label, Vector2(viewport.size)):
		return
	if not _assert_inside_viewport(board_frame, Vector2(viewport.size)):
		return
	if not _assert_inside_viewport(undo_button, Vector2(viewport.size)):
		return
	if not _assert_inside_viewport(new_game_button, Vector2(viewport.size)):
		return
	if not _assert_inside_viewport(back_to_menu_button, Vector2(viewport.size)):
		return

	game.free()
	viewport.free()
	print("IPHONE_PORTRAIT_UI_TASK_TESTS PASS")
	get_tree().quit()
