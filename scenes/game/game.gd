extends Control

const _GameLogic = preload("res://scripts/game_logic.gd")
const _PlayerController = preload("res://scripts/player/player_controller.gd")

@onready var horizontal_layout: HBoxContainer = %HorizontalLayout
@onready var vertical_layout: VBoxContainer = %VerticalLayout
@onready var horizontal_panel_content: VBoxContainer = %HorizontalPanelContent
@onready var vertical_status: MarginContainer = %VerticalStatus
@onready var horizontal_board_host: CenterContainer = %HorizontalBoardHost
@onready var vertical_board_host: CenterContainer = %VerticalBoardHost
@onready var board_frame: Control = %BoardFrame
@onready var vertical_actions: MarginContainer = %VerticalActions
@onready var status_container: VBoxContainer = %StatusContainer
@onready var actions_container: VBoxContainer = %ActionsContainer
@onready var spacer: Control = %Spacer
@onready var board: Node2D = %Board
@onready var turn_label: Label = %TurnLabel
@onready var color_label: Label = %ColorLabel
@onready var move_label: Label = %MoveLabel
@onready var message_label: Label = %MessageLabel
@onready var undo_button: Button = %UndoButton
@onready var new_game_button: Button = %NewGameButton
@onready var back_to_menu_button: Button = %BackToMenuButton
@onready var resign_button: Button = %ResignButton
@onready var confirm_dialog: ConfirmationDialog = %ConfirmDialog
@onready var game_over_panel: PanelContainer = %GameOverPanel
@onready var result_label: Label = %ResultLabel
@onready var play_again_button: Button = %PlayAgainButton
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

	undo_button.pressed.connect(_on_undo_pressed)
	new_game_button.pressed.connect(_confirm_new_game)
	back_to_menu_button.pressed.connect(_confirm_main_menu)
	resign_button.pressed.connect(_on_resign_pressed)
	play_again_button.pressed.connect(_on_play_again_pressed)
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
	_disconnect_if_connected(NetworkManager.player_disconnected, _on_player_disconnected)
	if is_inside_tree():
		_disconnect_if_connected(get_viewport().size_changed, _apply_responsive_layout)


func _disconnect_if_connected(sig: Signal, callable: Callable) -> void:
	if sig.is_connected(callable):
		sig.disconnect(callable)


func _configure_for_mode() -> void:
	undo_button.visible = GameManager.mode == GameManager.GameMode.LOCAL_PVP or GameManager.mode == GameManager.GameMode.VS_AI
	_update_undo_enabled()
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


func _apply_responsive_layout() -> void:
	var size: Vector2i = get_viewport_rect().size
	var use_vertical: bool = OS.get_name() == "iOS" and size.y > size.x
	vertical_layout.visible = use_vertical
	horizontal_layout.visible = not use_vertical

	var board_size: float = 620.0
	if use_vertical:
		board_size = minf(float(size.x) - 24.0, 620.0)
	board_size = maxf(board_size, 240.0)

	board_frame.custom_minimum_size = Vector2(board_size, board_size)
	if "board_pixel_size" in board:
		board.board_pixel_size = board_size
	board.queue_redraw()

	if use_vertical:
		_reparent_if_needed(status_container, vertical_status)
		_reparent_if_needed(board_frame, vertical_board_host)
		_reparent_if_needed(actions_container, vertical_actions)
		spacer.visible = false
	else:
		_reparent_if_needed(status_container, horizontal_panel_content, 0)
		_reparent_if_needed(board_frame, horizontal_board_host)
		_reparent_if_needed(actions_container, horizontal_panel_content)
		spacer.visible = true
		if spacer.get_parent() != horizontal_panel_content:
			horizontal_panel_content.add_child(spacer)
			horizontal_panel_content.move_child(spacer, 1)


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
	if GameManager.forbidden_enabled:
		return " · 禁手"
	return ""


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


func _on_stone_placed(_row: int, _col: int, _color: int) -> void:
	move_label.text = "步数：%d" % GameManager.logic.move_history.size()
	message_label.text = ""
	_update_undo_enabled()


func _on_history_changed() -> void:
	move_label.text = "步数：%d" % GameManager.logic.move_history.size()
	message_label.text = ""
	if "queue_redraw" in board:
		board.queue_redraw()
	_update_undo_enabled()


func _update_undo_enabled() -> void:
	undo_button.disabled = GameManager.logic.game_over \
		or GameManager.logic.move_history.is_empty() \
		or not (GameManager.mode == GameManager.GameMode.LOCAL_PVP or GameManager.mode == GameManager.GameMode.VS_AI)


func _on_invalid_human_move(message: String) -> void:
	_show_message(message)


func _show_message(message: String) -> void:
	_message_token += 1
	var token: int = _message_token
	message_label.text = message
	message_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.25))
	await get_tree().create_timer(1.6).timeout
	if token == _message_token:
		message_label.text = ""


func _on_game_ended(winner: int) -> void:
	_update_undo_enabled()
	game_over_panel.visible = true
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
	move_label.text = "步数：0"
	message_label.text = ""
	_update_undo_enabled()


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
			GameManager.game_ended.emit(opponent_color)
		GameManager.GameMode.ONLINE:
			var opponent_color: int = _GameLogic.WHITE if GameManager.my_color == _GameLogic.BLACK else _GameLogic.BLACK
			GameManager.logic.game_over = true
			GameManager.logic.winner = opponent_color
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
	game_over_panel.visible = true
	result_label.text = "对手已断开"
	result_label.add_theme_color_override("font_color", Color.RED)
	play_again_button.visible = false
