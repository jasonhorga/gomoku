extends Control

const _GameLogic = preload("res://scripts/game_logic.gd")
const _PlayerController = preload("res://scripts/player/player_controller.gd")

const PORTRAIT_BOARD_MIN: float = 300.0
const PHONE_SIDE_MARGIN_RATIO: float = 0.04
const PHONE_SIDE_MARGIN_MIN: float = 14.0
const PHONE_SIDE_MARGIN_MAX: float = 18.0
const PHONE_PROMAX_BOARD_TARGET_MIN: float = 396.0
const PHONE_PROMAX_BOARD_TARGET_MAX: float = 408.0
const PHONE_STATUS_HEIGHT_PROMAX: float = 108.0
const PHONE_ACTION_HEIGHT_PROMAX: float = 56.0
const PHONE_ACTION_HEIGHT_SMALL: float = 52.0
const PHONE_ACTION_GAP: float = 10.0
const PHONE_TOP_CHROME: float = 18.0
const PHONE_BOTTOM_CHROME: float = 18.0

@onready var horizontal_layout: HBoxContainer = %HorizontalLayout
@onready var vertical_layout: VBoxContainer = %VerticalLayout
@onready var horizontal_panel_content: VBoxContainer = %HorizontalPanelContent
@onready var vertical_status: MarginContainer = %VerticalStatus
@onready var vertical_status_card: PanelContainer = %VerticalStatusCard
@onready var vertical_status_card_padding: MarginContainer = %VerticalStatusCardPadding
@onready var horizontal_board_host: CenterContainer = %HorizontalBoardHost
@onready var vertical_board_host: CenterContainer = %VerticalBoardHost
@onready var board_frame: Control = %BoardFrame
@onready var vertical_actions: MarginContainer = %VerticalActions
@onready var vertical_actions_card: PanelContainer = %VerticalActionsCard
@onready var vertical_actions_card_padding: MarginContainer = %VerticalActionsCardPadding
@onready var status_container: VBoxContainer = %StatusContainer
@onready var actions_container: VBoxContainer = %ActionsContainer
@onready var spacer: Control = %Spacer
@onready var board: Node2D = %Board
@onready var turn_label: Label = %TurnLabel
@onready var color_label: Label = %ColorLabel
@onready var move_label: Label = %MoveLabel
@onready var message_label: Label = %MessageLabel
@onready var undo_button: Button = %UndoButton
@onready var ai_watch_controls: HBoxContainer = %AiWatchControls
@onready var pause_button: Button = %PauseButton
@onready var step_button: Button = %StepButton
@onready var auto_button: Button = %AutoButton
@onready var new_game_button: Button = %NewGameButton
@onready var back_to_menu_button: Button = %BackToMenuButton
@onready var resign_button: Button = %ResignButton
@onready var confirm_dialog: ConfirmationDialog = %ConfirmDialog
@onready var game_over_panel: PanelContainer = %GameOverPanel
@onready var result_label: Label = %ResultLabel
@onready var play_again_button: Button = %PlayAgainButton
@onready var replay_button: Button = %ReplayButton
@onready var main_menu_button: Button = %MainMenuButton
@onready var reset_request_panel: PanelContainer = %ResetRequestPanel

var _message_token: int = 0
var _pending_confirmation: Callable = Callable()
var _resume_after_confirmation_cancel: bool = false


func _ready() -> void:
	GameManager.turn_changed.connect(_on_turn_changed)
	GameManager.stone_placed.connect(_on_stone_placed)
	GameManager.game_ended.connect(_on_game_ended)
	GameManager.invalid_human_move.connect(_on_invalid_human_move)
	GameManager.opponent_reset_requested.connect(_on_opponent_reset_requested)
	GameManager.game_reset.connect(_on_game_reset)
	GameManager.history_changed.connect(_on_history_changed)
	GameManager.ai_watch_state_changed.connect(_update_ai_watch_controls)

	undo_button.pressed.connect(_on_undo_pressed)
	pause_button.pressed.connect(_on_pause_pressed)
	step_button.pressed.connect(_on_step_pressed)
	auto_button.pressed.connect(_on_auto_pressed)
	new_game_button.pressed.connect(_confirm_new_game)
	back_to_menu_button.pressed.connect(_confirm_main_menu)
	resign_button.pressed.connect(_on_resign_pressed)
	play_again_button.pressed.connect(_on_play_again_pressed)
	replay_button.pressed.connect(_on_replay_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	%AcceptResetButton.pressed.connect(_on_accept_reset)
	%DeclineResetButton.pressed.connect(_on_decline_reset)
	confirm_dialog.confirmed.connect(_on_confirmed)
	confirm_dialog.canceled.connect(_on_confirmation_cancelled)
	confirm_dialog.close_requested.connect(_on_confirmation_cancelled)
	get_viewport().size_changed.connect(_apply_responsive_layout)

	game_over_panel.visible = false
	reset_request_panel.visible = false

	_configure_for_mode()
	_apply_responsive_layout()
	GameManager.start_game()


func _exit_tree() -> void:
	_disconnect_if_connected(GameManager.turn_changed, _on_turn_changed)
	_disconnect_if_connected(GameManager.stone_placed, _on_stone_placed)
	_disconnect_if_connected(GameManager.game_ended, _on_game_ended)
	_disconnect_if_connected(GameManager.invalid_human_move, _on_invalid_human_move)
	_disconnect_if_connected(GameManager.opponent_reset_requested, _on_opponent_reset_requested)
	_disconnect_if_connected(GameManager.game_reset, _on_game_reset)
	_disconnect_if_connected(GameManager.history_changed, _on_history_changed)
	_disconnect_if_connected(GameManager.ai_watch_state_changed, _update_ai_watch_controls)
	_disconnect_if_connected(NetworkManager.player_disconnected, _on_player_disconnected)
	if is_inside_tree():
		_disconnect_if_connected(get_viewport().size_changed, _apply_responsive_layout)


func _disconnect_if_connected(sig: Signal, callable: Callable) -> void:
	if sig.is_connected(callable):
		sig.disconnect(callable)


func _configure_for_mode() -> void:
	undo_button.visible = GameManager.mode == GameManager.GameMode.LOCAL_PVP or GameManager.mode == GameManager.GameMode.VS_AI
	_update_undo_enabled()
	_update_ai_watch_controls()
	new_game_button.visible = GameManager.mode != GameManager.GameMode.ONLINE
	back_to_menu_button.visible = GameManager.mode != GameManager.GameMode.ONLINE
	resign_button.visible = GameManager.mode == GameManager.GameMode.ONLINE

	match GameManager.mode:
		GameManager.GameMode.ONLINE:
			_update_color_label()
			resign_button.text = "认输"
			NetworkManager.player_disconnected.connect(_on_player_disconnected)
		GameManager.GameMode.LOCAL_PVP:
			color_label.text = "本地双人%s" % _ruleset_suffix()
		GameManager.GameMode.VS_AI:
			_update_color_label()
		GameManager.GameMode.AI_VS_AI:
			# Show which engines are fighting — before this just said
			# "AI vs AI", which made it impossible to tell L4 vs L6
			# from L5 vs L1 at a glance.
			color_label.text = "%s（黑）vs %s（白）%s" % [
				_friendly_engine_name(0), _friendly_engine_name(1), _ruleset_suffix()
			]


func _should_use_vertical_layout(size: Vector2i) -> bool:
	var is_portrait: bool = size.y > size.x
	var narrow_width: bool = size.x <= 700
	return is_portrait and narrow_width


func _visible_actions_minimum_height() -> float:
	var total_height: float = 0.0
	var visible_count: int = 0
	for child: Node in actions_container.get_children():
		var control := child as Control
		if control != null and control.visible:
			total_height += control.get_combined_minimum_size().y
			visible_count += 1
	var action_gap: float = float(actions_container.get_theme_constant("separation"))
	return total_height + maxf(float(visible_count - 1), 0.0) * action_gap


func _vertical_card_style_minimum_height() -> float:
	var total_height: float = 0.0
	for card: PanelContainer in [vertical_status_card, vertical_actions_card]:
		var panel_style := card.get_theme_stylebox("panel")
		if panel_style != null:
			total_height += panel_style.get_minimum_size().y
	return total_height


func _portrait_side_margin(width: float) -> float:
	return clampf(width * PHONE_SIDE_MARGIN_RATIO, PHONE_SIDE_MARGIN_MIN, PHONE_SIDE_MARGIN_MAX)


func _portrait_content_width(width: float) -> float:
	return roundf(width - _portrait_side_margin(width) * 2.0)


func _portrait_action_height(width: float) -> float:
	return PHONE_ACTION_HEIGHT_PROMAX if width >= 428.0 else PHONE_ACTION_HEIGHT_SMALL


func _visible_action_count() -> int:
	var visible_count: int = 0
	for child: Node in actions_container.get_children():
		var control := child as Control
		if control != null and control.visible:
			visible_count += 1
	return visible_count


func _sync_message_visibility() -> void:
	var hide_empty_portrait_message: bool = vertical_layout.visible and message_label.text == ""
	message_label.visible = not hide_empty_portrait_message


func _reset_portrait_chrome_baseline() -> void:
	vertical_layout.add_theme_constant_override("separation", 12)
	vertical_status.add_theme_constant_override("margin_left", 8)
	vertical_status.add_theme_constant_override("margin_top", 12)
	vertical_status.add_theme_constant_override("margin_right", 8)
	vertical_status.add_theme_constant_override("margin_bottom", 0)
	vertical_actions.add_theme_constant_override("margin_left", 8)
	vertical_actions.add_theme_constant_override("margin_top", 0)
	vertical_actions.add_theme_constant_override("margin_right", 8)
	vertical_actions.add_theme_constant_override("margin_bottom", 12)
	for padding: MarginContainer in [vertical_status_card_padding, vertical_actions_card_padding]:
		padding.add_theme_constant_override("margin_left", 4)
		padding.add_theme_constant_override("margin_top", 10)
		padding.add_theme_constant_override("margin_right", 4)
		padding.add_theme_constant_override("margin_bottom", 10)


func _apply_responsive_layout() -> void:
	var size: Vector2i = get_viewport_rect().size
	var use_vertical: bool = _should_use_vertical_layout(size)
	vertical_layout.visible = use_vertical
	horizontal_layout.visible = not use_vertical
	_apply_gameplay_readability(use_vertical)
	if use_vertical:
		_reset_portrait_chrome_baseline()

	var board_size: float = 620.0
	if use_vertical:
		var viewport_width: float = float(size.x)
		var viewport_height: float = float(size.y)
		var content_width: float = _portrait_content_width(viewport_width)
		var action_rows: int = max(1, _visible_action_count())
		var action_height: float = _portrait_action_height(viewport_width)
		var actions_height: float = float(action_rows) * action_height + float(max(0, action_rows - 1)) * PHONE_ACTION_GAP + 20.0
		var status_height: float = PHONE_STATUS_HEIGHT_PROMAX if viewport_width >= 428.0 else 96.0
		var vertical_chrome: float = PHONE_TOP_CHROME + status_height + 10.0 + actions_height + PHONE_BOTTOM_CHROME
		var width_budget: float = content_width
		var height_budget: float = viewport_height - vertical_chrome
		var responsive_min: float = 350.0 if viewport_width >= 390.0 else PORTRAIT_BOARD_MIN
		board_size = minf(minf(width_budget, maxf(height_budget, responsive_min)), 620.0)
		board_size = _fit_portrait_chrome_to_height(viewport_height, board_size, status_height, actions_height, responsive_min)
		board_size = maxf(board_size, responsive_min)
	else:
		board_size = maxf(board_size, 320.0)
	board_size = maxf(board_size, PORTRAIT_BOARD_MIN if use_vertical else 320.0)

	board_frame.custom_minimum_size = Vector2(board_size, board_size)
	if "board_pixel_size" in board:
		board.board_pixel_size = board_size
	board.queue_redraw()

	if use_vertical:
		var content_width: float = _portrait_content_width(float(size.x))
		vertical_status.custom_minimum_size.x = content_width
		vertical_actions.custom_minimum_size.x = content_width
		status_container.custom_minimum_size.x = content_width
		actions_container.custom_minimum_size.x = content_width
		_reparent_if_needed(status_container, vertical_status_card_padding)
		_reparent_if_needed(board_frame, vertical_board_host)
		_reparent_if_needed(actions_container, vertical_actions_card_padding)
		spacer.visible = false
		_fit_portrait_layout()
	else:
		vertical_status.custom_minimum_size.x = 0.0
		vertical_actions.custom_minimum_size.x = 0.0
		status_container.custom_minimum_size.x = 0.0
		actions_container.custom_minimum_size.x = 0.0
		_reparent_if_needed(status_container, horizontal_panel_content, 0)
		_reparent_if_needed(board_frame, horizontal_board_host)
		_reparent_if_needed(actions_container, horizontal_panel_content)
		spacer.visible = true
		if spacer.get_parent() != horizontal_panel_content:
			horizontal_panel_content.add_child(spacer)
			horizontal_panel_content.move_child(spacer, 1)


func _fit_portrait_chrome_to_height(viewport_height: float, board_size: float, status_height: float, action_rows_height: float, board_floor: float) -> float:
	var vertical_separation: float = float(vertical_layout.get_theme_constant("separation"))
	var outer_vertical_margin: float = float(vertical_status.get_theme_constant("margin_top") + vertical_status.get_theme_constant("margin_bottom"))
	outer_vertical_margin += float(vertical_actions.get_theme_constant("margin_top") + vertical_actions.get_theme_constant("margin_bottom"))
	var card_vertical_padding: float = float(vertical_status_card_padding.get_theme_constant("margin_top") + vertical_status_card_padding.get_theme_constant("margin_bottom"))
	card_vertical_padding += float(vertical_actions_card_padding.get_theme_constant("margin_top") + vertical_actions_card_padding.get_theme_constant("margin_bottom"))
	var total_height: float = board_size + status_height + action_rows_height + vertical_separation * 2.0 + outer_vertical_margin + card_vertical_padding + _vertical_card_style_minimum_height()
	var overflow: float = total_height - viewport_height
	if overflow <= 0.0:
		return board_size
	var reducible_padding: float = vertical_separation * 2.0 + outer_vertical_margin + card_vertical_padding
	var padding_scale: float = 0.0 if reducible_padding <= 0.0 else maxf((reducible_padding - overflow - 2.0) / reducible_padding, 0.0)
	var status_padding: int = int(roundf(10.0 * padding_scale))
	var actions_padding: int = int(roundf(10.0 * padding_scale))
	vertical_layout.add_theme_constant_override("separation", int(roundf(12.0 * padding_scale)))
	vertical_status.add_theme_constant_override("margin_top", int(roundf(12.0 * padding_scale)))
	vertical_actions.add_theme_constant_override("margin_bottom", int(roundf(12.0 * padding_scale)))
	vertical_status_card_padding.add_theme_constant_override("margin_top", status_padding)
	vertical_status_card_padding.add_theme_constant_override("margin_bottom", status_padding)
	vertical_actions_card_padding.add_theme_constant_override("margin_top", actions_padding)
	vertical_actions_card_padding.add_theme_constant_override("margin_bottom", actions_padding)
	var remaining_overflow: float = maxf(overflow - reducible_padding, 0.0)
	return maxf(board_size - remaining_overflow, board_floor)


func _make_card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.20, 0.12, 0.07, 0.92)
	style.border_color = Color(0.55, 0.38, 0.20, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 3)
	return style


func _make_button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.set_content_margin(SIDE_LEFT, 14.0)
	style.set_content_margin(SIDE_RIGHT, 14.0)
	return style


func _apply_gameplay_readability(use_vertical: bool) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var viewport_width: float = float(viewport_size.x)
	var viewport_height: float = float(viewport_size.y)
	var compact_portrait: bool = use_vertical and viewport_height < 720.0
	var is_large_phone: bool = use_vertical and viewport_width >= 428.0
	var status_font_size: int = 24 if compact_portrait else (32 if use_vertical else 24)
	var color_font_size: int = 16 if compact_portrait else (20 if use_vertical else 18)
	var detail_font_size: int = 13 if compact_portrait else 16
	var message_font_size: int = 16 if is_large_phone else detail_font_size
	var action_font_size: int = 17 if compact_portrait else (20 if use_vertical else 18)
	var action_height: float = _portrait_action_height(viewport_width) if use_vertical else 52.0
	var fill_horizontal: int = Control.SIZE_EXPAND_FILL if use_vertical else Control.SIZE_FILL
	var ai_watch_fill_horizontal: int = Control.SIZE_EXPAND_FILL
	var label_alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER if use_vertical else HORIZONTAL_ALIGNMENT_LEFT

	turn_label.add_theme_font_size_override("font_size", status_font_size)
	color_label.add_theme_font_size_override("font_size", color_font_size)
	move_label.add_theme_font_size_override("font_size", detail_font_size)
	message_label.add_theme_font_size_override("font_size", message_font_size)
	turn_label.horizontal_alignment = label_alignment
	color_label.horizontal_alignment = label_alignment
	move_label.horizontal_alignment = label_alignment
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sync_message_visibility()
	vertical_layout.add_theme_constant_override("separation", 12 if use_vertical else 8)
	status_container.add_theme_constant_override("separation", 4 if compact_portrait else (8 if use_vertical else 15))
	actions_container.add_theme_constant_override("separation", 6 if compact_portrait else (12 if use_vertical else 10))
	status_container.size_flags_horizontal = fill_horizontal
	actions_container.size_flags_horizontal = fill_horizontal
	vertical_status_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vertical_actions_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	for button: Button in [undo_button, new_game_button, back_to_menu_button, resign_button]:
		button.custom_minimum_size.y = action_height
		button.size_flags_horizontal = fill_horizontal
		button.add_theme_font_size_override("font_size", action_font_size)
	for button: Button in [pause_button, step_button, auto_button]:
		button.custom_minimum_size.y = action_height
		button.size_flags_horizontal = ai_watch_fill_horizontal if not use_vertical else Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", action_font_size)

	var styled_buttons: Array[Button] = [undo_button, pause_button, step_button, auto_button, new_game_button, back_to_menu_button, resign_button]
	if use_vertical:
		vertical_status_card.add_theme_stylebox_override("panel", _make_card_style())
		vertical_actions_card.add_theme_stylebox_override("panel", _make_card_style())
		var normal_style := _make_button_style(Color(0.64, 0.39, 0.18, 1.0), Color(0.86, 0.60, 0.30, 0.9))
		var hover_style := _make_button_style(Color(0.72, 0.46, 0.22, 1.0), Color(0.95, 0.70, 0.38, 1.0))
		var pressed_style := _make_button_style(Color(0.48, 0.28, 0.13, 1.0), Color(0.74, 0.48, 0.22, 1.0))
		var disabled_style := _make_button_style(Color(0.34, 0.28, 0.22, 1.0), Color(0.50, 0.42, 0.34, 0.75))
		for button: Button in styled_buttons:
			button.add_theme_stylebox_override("normal", normal_style)
			button.add_theme_stylebox_override("hover", hover_style)
			button.add_theme_stylebox_override("pressed", pressed_style)
			button.add_theme_stylebox_override("disabled", disabled_style)
	else:
		vertical_status_card.remove_theme_stylebox_override("panel")
		vertical_actions_card.remove_theme_stylebox_override("panel")
		for button: Button in styled_buttons:
			button.remove_theme_stylebox_override("normal")
			button.remove_theme_stylebox_override("hover")
			button.remove_theme_stylebox_override("pressed")
			button.remove_theme_stylebox_override("disabled")


func _fit_portrait_layout() -> void:
	if not vertical_layout.visible:
		return
	var viewport_height: float = float(get_viewport_rect().size.y)
	var overflow: float = vertical_layout.get_combined_minimum_size().y - viewport_height
	if overflow <= 0.0:
		return
	var viewport_width: float = float(get_viewport_rect().size.x)
	var responsive_min: float = 350.0 if viewport_width >= 390.0 else PORTRAIT_BOARD_MIN
	var current_board_size: float = board_frame.custom_minimum_size.x
	var board_reduction: float = minf(overflow, maxf(current_board_size - responsive_min, 0.0))
	var board_size: float = current_board_size - board_reduction
	if board_size < current_board_size:
		board_frame.custom_minimum_size = Vector2(board_size, board_size)
		if "board_pixel_size" in board:
			board.board_pixel_size = board_size
		board.queue_redraw()
	var remaining_overflow: float = overflow - board_reduction
	if remaining_overflow > 0.0:
		_compress_portrait_chrome_for_overflow(remaining_overflow)


func _compress_portrait_chrome_for_overflow(overflow: float) -> void:
	var vertical_separation: float = float(vertical_layout.get_theme_constant("separation"))
	var status_top: float = float(vertical_status.get_theme_constant("margin_top"))
	var status_bottom: float = float(vertical_status.get_theme_constant("margin_bottom"))
	var actions_top: float = float(vertical_actions.get_theme_constant("margin_top"))
	var actions_bottom: float = float(vertical_actions.get_theme_constant("margin_bottom"))
	var status_padding_top: float = float(vertical_status_card_padding.get_theme_constant("margin_top"))
	var status_padding_bottom: float = float(vertical_status_card_padding.get_theme_constant("margin_bottom"))
	var actions_padding_top: float = float(vertical_actions_card_padding.get_theme_constant("margin_top"))
	var actions_padding_bottom: float = float(vertical_actions_card_padding.get_theme_constant("margin_bottom"))
	var reducible: float = vertical_separation * 2.0 + status_top + status_bottom + actions_top + actions_bottom
	reducible += status_padding_top + status_padding_bottom + actions_padding_top + actions_padding_bottom
	if reducible <= 0.0:
		return
	var scale: float = maxf((reducible - overflow - 2.0) / reducible, 0.0)
	vertical_layout.add_theme_constant_override("separation", int(roundf(vertical_separation * scale)))
	vertical_status.add_theme_constant_override("margin_top", int(roundf(status_top * scale)))
	vertical_status.add_theme_constant_override("margin_bottom", int(roundf(status_bottom * scale)))
	vertical_actions.add_theme_constant_override("margin_top", int(roundf(actions_top * scale)))
	vertical_actions.add_theme_constant_override("margin_bottom", int(roundf(actions_bottom * scale)))
	vertical_status_card_padding.add_theme_constant_override("margin_top", int(roundf(status_padding_top * scale)))
	vertical_status_card_padding.add_theme_constant_override("margin_bottom", int(roundf(status_padding_bottom * scale)))
	vertical_actions_card_padding.add_theme_constant_override("margin_top", int(roundf(actions_padding_top * scale)))
	vertical_actions_card_padding.add_theme_constant_override("margin_bottom", int(roundf(actions_padding_bottom * scale)))


func _reparent_if_needed(node: Node, new_parent: Node, index: int = -1) -> void:
	if node.get_parent() == new_parent:
		if index >= 0:
			new_parent.move_child(node, index)
		return
	node.reparent(new_parent, false)
	if index >= 0:
		new_parent.move_child(node, index)


func _update_color_label() -> void:
	# Vs-AI: say who you're playing against so the HUD doesn't just say
	# "AI" with no context.
	var opponent_idx: int = 1 if GameManager.my_color == _GameLogic.BLACK else 0
	var opp_name: String = _friendly_engine_name(opponent_idx)
	if GameManager.my_color == _GameLogic.BLACK:
		color_label.text = "你执黑 ●  vs  %s%s" % [opp_name, _ruleset_suffix()]
	else:
		color_label.text = "你执白 ○  vs  %s%s" % [opp_name, _ruleset_suffix()]


func _ruleset_suffix() -> String:
	return "（禁手规则）" if GameManager.forbidden_enabled else "（自由五子棋）"


func _friendly_engine_name(player_idx: int) -> String:
	var p: Variant = GameManager.players[player_idx] if player_idx < GameManager.players.size() else null
	if p == null:
		return "?"
	if "ai_engine" in p and p.ai_engine != null and p.ai_engine.has_method("get_name"):
		return p.ai_engine.get_name()
	# Human / no engine: just say which side.
	return "玩家" if p.player_type == _PlayerController.Type.LOCAL_HUMAN else "AI"


func _on_turn_changed(_is_my_turn: bool) -> void:
	_update_undo_enabled()
	_update_ai_watch_controls()
	match GameManager.mode:
		GameManager.GameMode.LOCAL_PVP:
			if GameManager.logic.current_player == _GameLogic.BLACK:
				turn_label.text = "▶ 黑方回合"
			else:
				turn_label.text = "▶ 白方回合"
			turn_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
		GameManager.GameMode.VS_AI:
			if _is_my_turn:
				turn_label.text = "▶ 你的回合"
				turn_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
			else:
				turn_label.text = "AI 思考中..."
				turn_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
		GameManager.GameMode.AI_VS_AI:
			if GameManager.logic.current_player == _GameLogic.BLACK:
				turn_label.text = "黑方 AI..."
			else:
				turn_label.text = "白方 AI..."
			turn_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
		_:  # ONLINE
			if _is_my_turn:
				turn_label.text = "▶ 你的回合"
				turn_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
			else:
				turn_label.text = "对手回合"
				turn_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_apply_responsive_layout()


func _on_stone_placed(_row: int, _col: int, _color: int) -> void:
	move_label.text = "步数：%d" % GameManager.logic.move_history.size()
	message_label.text = ""
	_sync_message_visibility()
	_update_undo_enabled()
	_update_ai_watch_controls()


func _on_history_changed() -> void:
	move_label.text = "步数：%d" % GameManager.logic.move_history.size()
	message_label.text = ""
	_sync_message_visibility()
	if "queue_redraw" in board:
		board.queue_redraw()
	_update_undo_enabled()


func _update_undo_enabled() -> void:
	undo_button.disabled = not GameManager.can_undo_last_turn()


func _update_ai_watch_controls() -> void:
	var is_ai_watch: bool = GameManager.mode == GameManager.GameMode.AI_VS_AI
	ai_watch_controls.visible = is_ai_watch
	if not is_ai_watch:
		return
	var game_over: bool = GameManager.logic.game_over
	pause_button.disabled = game_over or GameManager.ai_watch_paused
	step_button.disabled = game_over or GameManager.ai_move_in_progress
	auto_button.disabled = game_over or (not GameManager.ai_watch_paused and not GameManager.ai_move_in_progress)


func _on_pause_pressed() -> void:
	GameManager.set_ai_watch_paused(true)
	_update_ai_watch_controls()


func _on_step_pressed() -> void:
	GameManager.request_ai_watch_step()
	_update_ai_watch_controls()


func _on_auto_pressed() -> void:
	GameManager.set_ai_watch_paused(false)
	_update_ai_watch_controls()


func _on_invalid_human_move(message: String) -> void:
	_show_message(message)


func _show_message(message: String) -> void:
	_message_token += 1
	var token: int = _message_token
	message_label.text = message
	_sync_message_visibility()
	message_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.25))
	await get_tree().create_timer(1.6).timeout
	if token == _message_token:
		message_label.text = ""
	_sync_message_visibility()


func _on_game_ended(winner: int) -> void:
	_update_undo_enabled()
	_update_ai_watch_controls()
	game_over_panel.visible = true
	replay_button.visible = GameManager.last_game_record != null
	replay_button.disabled = GameManager.last_game_record == null
	play_again_button.visible = true
	play_again_button.text = "再来一局"
	play_again_button.disabled = false

	match GameManager.mode:
		GameManager.GameMode.LOCAL_PVP:
			if winner == _GameLogic.EMPTY:
				result_label.text = "平局！"
				result_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			elif winner == _GameLogic.BLACK:
				result_label.text = "黑方获胜！"
				result_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
			else:
				result_label.text = "白方获胜！"
				result_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
		_:  # ONLINE, VS_AI
			if winner == _GameLogic.EMPTY:
				result_label.text = "平局！"
				result_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			elif winner == GameManager.my_color:
				result_label.text = "你赢了！"
				result_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
			else:
				result_label.text = "你输了"
				result_label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2))


func _on_game_reset() -> void:
	game_over_panel.visible = false
	reset_request_panel.visible = false
	replay_button.visible = true
	replay_button.disabled = false
	move_label.text = "步数：0"
	message_label.text = ""
	_sync_message_visibility()
	_update_undo_enabled()
	_update_ai_watch_controls()


func _on_undo_pressed() -> void:
	if GameManager.has_method("undo_last_turn"):
		GameManager.undo_last_turn()
	else:
		_show_message("悔棋功能即将加入")


func _confirm_new_game() -> void:
	_pause_game_for_confirmation(Callable(GameManager, "request_reset"), "确定开始新对局吗？")


func _confirm_main_menu() -> void:
	_pause_game_for_confirmation(Callable(self, "_go_to_main_menu"), "确定返回主菜单吗？")


func _pause_game_for_confirmation(action: Callable, message: String) -> void:
	_pending_confirmation = action
	_resume_after_confirmation_cancel = not GameManager.logic.game_over
	if _resume_after_confirmation_cancel:
		GameManager.pause_current_move()
	confirm_dialog.dialog_text = message
	confirm_dialog.popup_centered()


func _on_confirmed() -> void:
	_resume_after_confirmation_cancel = false
	var action: Callable = _pending_confirmation
	_pending_confirmation = Callable()
	if action.is_valid():
		action.call()


func _on_confirmation_cancelled() -> void:
	_pending_confirmation = Callable()
	if _resume_after_confirmation_cancel:
		_resume_after_confirmation_cancel = false
		GameManager.resume_current_move()


func _on_resign_pressed() -> void:
	match GameManager.mode:
		GameManager.GameMode.VS_AI:
			var opponent_color: int = _GameLogic.WHITE if GameManager.my_color == _GameLogic.BLACK else _GameLogic.BLACK
			GameManager.logic.game_over = true
			GameManager.logic.winner = opponent_color
			GameManager.last_game_record = null
			GameManager.game_ended.emit(opponent_color)
		GameManager.GameMode.ONLINE:
			var opponent_color: int = _GameLogic.WHITE if GameManager.my_color == _GameLogic.BLACK else _GameLogic.BLACK
			GameManager.logic.game_over = true
			GameManager.logic.winner = opponent_color
			GameManager.last_game_record = null
			GameManager.game_ended.emit(opponent_color)
			NetworkManager.send_move(-1, -1)  # resign signal
		GameManager.GameMode.AI_VS_AI:
			# Stop — go back to menu
			_on_main_menu_pressed()
		_:
			pass


func _on_play_again_pressed() -> void:
	if GameManager.mode == GameManager.GameMode.ONLINE:
		play_again_button.text = "等待中..."
		play_again_button.disabled = true
		GameManager.request_reset()
	else:
		GameManager.request_reset()


func _on_replay_pressed() -> void:
	if not GameManager.prepare_replay_from_last_game():
		_show_message("暂无可复盘的棋局")
		return
	GameManager._cancel_current_move()
	if GameManager.mode == GameManager.GameMode.ONLINE:
		NetworkManager.disconnect_from_game()
	GameManager.replay_return_scene = "res://scenes/main_menu/main_menu.tscn"
	get_tree().change_scene_to_file("res://scenes/replay/replay.tscn")


func _on_main_menu_pressed() -> void:
	_go_to_main_menu()


func _go_to_main_menu() -> void:
	GameManager._cancel_current_move()
	if GameManager.mode == GameManager.GameMode.ONLINE:
		NetworkManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")


func _on_opponent_reset_requested() -> void:
	reset_request_panel.visible = true


func _on_accept_reset() -> void:
	reset_request_panel.visible = false
	game_over_panel.visible = false
	GameManager.accept_reset()


func _on_decline_reset() -> void:
	reset_request_panel.visible = false


func _on_player_disconnected(_id: int) -> void:
	GameManager.last_game_record = null
	game_over_panel.visible = true
	replay_button.visible = false
	replay_button.disabled = true
	result_label.text = "对手已断开"
	result_label.add_theme_color_override("font_color", Color.RED)
	play_again_button.visible = false
