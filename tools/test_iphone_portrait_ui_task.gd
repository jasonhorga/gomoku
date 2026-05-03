extends Node

const SHORT_PORTRAIT_BOARD_MIN := 300.0

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


func _assert_centered_x(control: Control, viewport_width: float, tolerance: float, message: String) -> bool:
	var rect := control.get_global_rect()
	var center_x := rect.position.x + rect.size.x * 0.5
	var expected_center_x := viewport_width * 0.5
	return _expect(
		abs(center_x - expected_center_x) <= tolerance,
		"%s (center_x=%.1f, expected=%.1f, tolerance=%.1f, rect=%s)" % [message, center_x, expected_center_x, tolerance, rect]
	)


func _assert_min_width(control: Control, min_width: float, message: String) -> bool:
	var rect := control.get_global_rect()
	return _expect(
		rect.size.x >= min_width,
		"%s (width=%.1f, min=%.1f, rect=%s)" % [message, rect.size.x, min_width, rect]
	)


func _new_game_in_viewport(viewport_size: Vector2i) -> Dictionary:
	GameManager.setup_local_pvp(true)
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	viewport.disable_3d = true
	get_tree().root.add_child(viewport)
	var scene: PackedScene = load("res://scenes/game/game.tscn")
	assert(scene != null)
	var game = scene.instantiate()
	viewport.add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	return {"viewport": viewport, "game": game}


func _free_fixture(fixture: Dictionary) -> void:
	fixture.game.free()
	fixture.viewport.free()


func _assert_common_portrait_layout(game: Node, viewport_size: Vector2i) -> bool:
	var vertical_layout := _find_node(game, "VerticalLayout") as VBoxContainer
	var horizontal_layout := _find_node(game, "HorizontalLayout") as HBoxContainer
	var turn_label := _find_node(game, "TurnLabel") as Label
	var color_label := _find_node(game, "ColorLabel") as Label
	var move_label := _find_node(game, "MoveLabel") as Label
	var message_label := _find_node(game, "MessageLabel") as Label
	var status_container := _find_node(game, "StatusContainer") as VBoxContainer
	var actions_container := _find_node(game, "ActionsContainer") as VBoxContainer

	if not _expect(vertical_layout.visible == true, "VerticalLayout should be visible"):
		return false
	if not _expect(horizontal_layout.visible == false, "HorizontalLayout should be hidden"):
		return false
	var compact_portrait: bool = viewport_size.y < 720
	var min_turn_size: int = 24 if compact_portrait else 30
	var min_color_size: int = 16 if compact_portrait else 20
	var min_detail_size: int = 13 if compact_portrait else 16
	if not _expect(turn_label.get_theme_font_size("font_size") >= min_turn_size, "TurnLabel font is too small"):
		return false
	if not _expect(color_label.get_theme_font_size("font_size") >= min_color_size, "ColorLabel font is too small"):
		return false
	if not _expect(move_label.get_theme_font_size("font_size") >= min_detail_size, "MoveLabel font is too small"):
		return false
	if not _expect(message_label.get_theme_font_size("font_size") >= min_detail_size, "MessageLabel font is too small"):
		return false
	var min_action_separation: int = 6 if compact_portrait else 12
	if not _expect(status_container.get_theme_constant("separation") <= 8, "StatusContainer separation is too large"):
		return false
	if not _expect(actions_container.get_theme_constant("separation") >= min_action_separation, "ActionsContainer separation is too small"):
		return false
	if not _expect(turn_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "TurnLabel should be centered in portrait"):
		return false
	if not _expect(color_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "ColorLabel should be centered in portrait"):
		return false
	if not _expect(move_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "MoveLabel should be centered in portrait"):
		return false
	if not _expect(status_container.get_global_rect().intersects(actions_container.get_global_rect()) == false, "StatusContainer overlaps ActionsContainer"):
		return false
	if not _assert_inside_viewport(vertical_layout, Vector2(viewport_size)):
		return false
	return true


func _assert_portrait_buttons(game: Node, viewport_size: Vector2i, min_width: float, min_height: float) -> bool:
	var undo_button := _find_node(game, "UndoButton") as Button
	var new_game_button := _find_node(game, "NewGameButton") as Button
	var back_to_menu_button := _find_node(game, "BackToMenuButton") as Button
	for button: Button in [undo_button, new_game_button, back_to_menu_button]:
		if not _expect(button.custom_minimum_size.y >= min_height, "%s minimum height is too small" % button.name):
			return false
		if not _expect(button.size.y >= min_height, "%s rendered height is too small" % button.name):
			return false
		if not _assert_min_width(button, min_width, "%s should be full-width in portrait" % button.name):
			return false
		if not _assert_inside_viewport(button, Vector2(viewport_size)):
			return false
	return true


func _assert_portrait_style_overrides(game: Node) -> bool:
	var vertical_status_card := _find_node(game, "VerticalStatusCard") as PanelContainer
	var vertical_actions_card := _find_node(game, "VerticalActionsCard") as PanelContainer
	var undo_button := _find_node(game, "UndoButton") as Button
	if not _expect(vertical_status_card.has_theme_stylebox_override("panel"), "VerticalStatusCard should have a portrait panel style override"):
		return false
	if not _expect(vertical_actions_card.has_theme_stylebox_override("panel"), "VerticalActionsCard should have a portrait panel style override"):
		return false
	if not _expect(undo_button.has_theme_stylebox_override("normal"), "UndoButton should have a portrait normal style override"):
		return false
	if not _expect(undo_button.has_theme_stylebox_override("pressed"), "UndoButton should have a portrait pressed style override"):
		return false
	if not _expect(undo_button.has_theme_stylebox_override("disabled"), "UndoButton should have a portrait disabled style override"):
		return false
	return true


func _assert_horizontal_style_overrides_cleared(game: Node) -> bool:
	var vertical_status_card := _find_node(game, "VerticalStatusCard") as PanelContainer
	var vertical_actions_card := _find_node(game, "VerticalActionsCard") as PanelContainer
	var undo_button := _find_node(game, "UndoButton") as Button
	if not _expect(not vertical_status_card.has_theme_stylebox_override("panel"), "VerticalStatusCard should not keep portrait panel override in landscape"):
		return false
	if not _expect(not vertical_actions_card.has_theme_stylebox_override("panel"), "VerticalActionsCard should not keep portrait panel override in landscape"):
		return false
	if not _expect(not undo_button.has_theme_stylebox_override("normal"), "UndoButton should not keep portrait normal override in landscape"):
		return false
	if not _expect(not undo_button.has_theme_stylebox_override("pressed"), "UndoButton should not keep portrait pressed override in landscape"):
		return false
	if not _expect(not undo_button.has_theme_stylebox_override("disabled"), "UndoButton should not keep portrait disabled override in landscape"):
		return false
	return true


func _assert_portrait_content(game: Node, viewport_size: Vector2i, board_min: float, content_min: float) -> bool:
	var vertical_status := _find_node(game, "VerticalStatus") as MarginContainer
	var vertical_actions := _find_node(game, "VerticalActions") as MarginContainer
	var status_container := _find_node(game, "StatusContainer") as VBoxContainer
	var actions_container := _find_node(game, "ActionsContainer") as VBoxContainer
	var board_frame := _find_node(game, "BoardFrame") as Control
	var turn_label := _find_node(game, "TurnLabel") as Label
	var message_label := _find_node(game, "MessageLabel") as Label

	if not _assert_min_width(board_frame, board_min, "BoardFrame should be wide enough for iPhone portrait viewport=%s" % viewport_size):
		return false
	if not _assert_min_width(vertical_status, content_min, "VerticalStatus should span the readable portrait width"):
		return false
	if not _assert_min_width(status_container, content_min, "StatusContainer should span the readable portrait width"):
		return false
	if not _assert_min_width(vertical_actions, content_min, "VerticalActions should span the readable portrait width"):
		return false
	if not _assert_min_width(actions_container, content_min, "ActionsContainer should span the readable portrait width"):
		return false
	if not _assert_centered_x(board_frame, float(viewport_size.x), 3.0, "BoardFrame should be horizontally centered in iPhone portrait"):
		return false
	if not _assert_centered_x(vertical_status, float(viewport_size.x), 3.0, "VerticalStatus should be horizontally centered in iPhone portrait"):
		return false
	if not _assert_centered_x(status_container, float(viewport_size.x), 3.0, "StatusContainer should be horizontally centered in iPhone portrait"):
		return false
	if not _assert_centered_x(vertical_actions, float(viewport_size.x), 3.0, "VerticalActions should be horizontally centered in iPhone portrait"):
		return false
	if not _assert_centered_x(actions_container, float(viewport_size.x), 3.0, "ActionsContainer should be horizontally centered in iPhone portrait"):
		return false
	if not _assert_inside_viewport(turn_label, Vector2(viewport_size)):
		return false
	if not _assert_inside_viewport(message_label, Vector2(viewport_size)):
		return false
	if not _assert_inside_viewport(board_frame, Vector2(viewport_size)):
		return false
	return true


func _assert_chrome_baseline(game: Node) -> bool:
	var vertical_layout := _find_node(game, "VerticalLayout") as VBoxContainer
	var vertical_status := _find_node(game, "VerticalStatus") as MarginContainer
	var vertical_actions := _find_node(game, "VerticalActions") as MarginContainer
	var status_padding := _find_node(game, "VerticalStatusCardPadding") as MarginContainer
	var actions_padding := _find_node(game, "VerticalActionsCardPadding") as MarginContainer
	if not _expect(vertical_layout.get_theme_constant("separation") >= 10, "VerticalLayout separation should not stay fully compressed after resize"):
		return false
	if not _expect(vertical_status.get_theme_constant("margin_left") == 8, "VerticalStatus left margin should reset to portrait baseline"):
		return false
	if not _expect(vertical_status.get_theme_constant("margin_top") == 12, "VerticalStatus top margin should reset to portrait baseline"):
		return false
	if not _expect(vertical_status.get_theme_constant("margin_right") == 8, "VerticalStatus right margin should reset to portrait baseline"):
		return false
	if not _expect(vertical_status.get_theme_constant("margin_bottom") == 0, "VerticalStatus bottom margin should reset to portrait baseline"):
		return false
	if not _expect(vertical_actions.get_theme_constant("margin_left") == 8, "VerticalActions left margin should reset to portrait baseline"):
		return false
	if not _expect(vertical_actions.get_theme_constant("margin_top") == 0, "VerticalActions top margin should reset to portrait baseline"):
		return false
	if not _expect(vertical_actions.get_theme_constant("margin_right") == 8, "VerticalActions right margin should reset to portrait baseline"):
		return false
	if not _expect(vertical_actions.get_theme_constant("margin_bottom") == 12, "VerticalActions bottom margin should reset to portrait baseline"):
		return false
	for padding: MarginContainer in [status_padding, actions_padding]:
		if not _expect(padding.get_theme_constant("margin_left") == 4, "%s left padding should reset to portrait baseline" % padding.name):
			return false
		if not _expect(padding.get_theme_constant("margin_top") == 10, "%s top padding should reset to portrait baseline" % padding.name):
			return false
		if not _expect(padding.get_theme_constant("margin_right") == 4, "%s right padding should reset to portrait baseline" % padding.name):
			return false
		if not _expect(padding.get_theme_constant("margin_bottom") == 10, "%s bottom padding should reset to portrait baseline" % padding.name):
			return false
	return true


func _test_standard_portrait() -> void:
	var fixture := await _new_game_in_viewport(Vector2i(390, 844))
	var game: Node = fixture.game
	var viewport: SubViewport = fixture.viewport
	if not _assert_common_portrait_layout(game, viewport.size):
		return
	if not _assert_portrait_buttons(game, viewport.size, 350.0, 52.0):
		return
	if not _assert_portrait_style_overrides(game):
		return
	if not _assert_portrait_content(game, viewport.size, 350.0, 350.0):
		return
	_free_fixture(fixture)


func _test_short_portrait() -> void:
	var fixture := await _new_game_in_viewport(Vector2i(375, 667))
	var game: Node = fixture.game
	var viewport: SubViewport = fixture.viewport
	if not _assert_common_portrait_layout(game, viewport.size):
		return
	if not _assert_portrait_buttons(game, viewport.size, 300.0, 40.0):
		return
	if not _assert_portrait_content(game, viewport.size, SHORT_PORTRAIT_BOARD_MIN, 300.0):
		return
	_free_fixture(fixture)


func _test_large_portrait() -> void:
	var fixture := await _new_game_in_viewport(Vector2i(430, 932))
	var game: Node = fixture.game
	var viewport: SubViewport = fixture.viewport
	if not _assert_common_portrait_layout(game, viewport.size):
		return
	if not _assert_portrait_buttons(game, viewport.size, 390.0, 52.0):
		return
	if not _assert_portrait_content(game, viewport.size, 390.0, 390.0):
		return
	_free_fixture(fixture)


func _test_resize_resets_portrait_chrome() -> void:
	var fixture := await _new_game_in_viewport(Vector2i(375, 667))
	var game: Node = fixture.game
	var viewport: SubViewport = fixture.viewport
	if not _assert_common_portrait_layout(game, viewport.size):
		return
	viewport.size = Vector2i(430, 932)
	await get_tree().process_frame
	await get_tree().process_frame
	if not _assert_chrome_baseline(game):
		return
	if not _assert_portrait_content(game, viewport.size, 390.0, 390.0):
		return
	_free_fixture(fixture)


func _test_horizontal_ai_watch_buttons_expand() -> void:
	var fixture := await _new_game_in_viewport(Vector2i(844, 390))
	var game: Node = fixture.game
	var horizontal_layout := _find_node(game, "HorizontalLayout") as HBoxContainer
	var vertical_layout := _find_node(game, "VerticalLayout") as VBoxContainer
	var pause_button := _find_node(game, "PauseButton") as Button
	var step_button := _find_node(game, "StepButton") as Button
	var auto_button := _find_node(game, "AutoButton") as Button
	if not _expect(horizontal_layout.visible == true, "HorizontalLayout should be visible in landscape"):
		return
	if not _expect(vertical_layout.visible == false, "VerticalLayout should be hidden in landscape"):
		return
	for button: Button in [pause_button, step_button, auto_button]:
		if not _expect(button.size_flags_horizontal == Control.SIZE_EXPAND_FILL, "%s should keep horizontal expand-fill in landscape AI-watch row" % button.name):
			return
	if not _assert_horizontal_style_overrides_cleared(game):
		return
	_free_fixture(fixture)


func _ready() -> void:
	await get_tree().process_frame
	await _test_standard_portrait()
	await _test_short_portrait()
	await _test_large_portrait()
	await _test_resize_resets_portrait_chrome()
	await _test_horizontal_ai_watch_buttons_expand()
	print("IPHONE_PORTRAIT_UI_TASK_TESTS PASS")
	get_tree().quit()
