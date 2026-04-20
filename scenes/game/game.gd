extends Control

const _GameLogic = preload("res://scripts/game_logic.gd")
const _PlayerController = preload("res://scripts/player/player_controller.gd")

@onready var turn_label: Label = %TurnLabel
@onready var color_label: Label = %ColorLabel
@onready var move_label: Label = %MoveLabel
@onready var resign_button: Button = %ResignButton
@onready var game_over_panel: PanelContainer = %GameOverPanel
@onready var result_label: Label = %ResultLabel
@onready var play_again_button: Button = %PlayAgainButton
@onready var main_menu_button: Button = %MainMenuButton
@onready var reset_request_panel: PanelContainer = %ResetRequestPanel


func _ready() -> void:
	GameManager.turn_changed.connect(_on_turn_changed)
	GameManager.stone_placed.connect(_on_stone_placed)
	GameManager.game_ended.connect(_on_game_ended)
	GameManager.opponent_reset_requested.connect(_on_opponent_reset_requested)
	GameManager.game_reset.connect(_on_game_reset)

	resign_button.pressed.connect(_on_resign_pressed)
	play_again_button.pressed.connect(_on_play_again_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	%AcceptResetButton.pressed.connect(_on_accept_reset)
	%DeclineResetButton.pressed.connect(_on_decline_reset)

	game_over_panel.visible = false
	reset_request_panel.visible = false

	_configure_for_mode()
	GameManager.start_game()


func _configure_for_mode() -> void:
	match GameManager.mode:
		GameManager.GameMode.ONLINE:
			_update_color_label()
			resign_button.text = "Resign"
			NetworkManager.player_disconnected.connect(_on_player_disconnected)
		GameManager.GameMode.LOCAL_PVP:
			color_label.text = ""
			resign_button.text = "New Game"
		GameManager.GameMode.VS_AI:
			_update_color_label()
			resign_button.text = "Resign"
		GameManager.GameMode.AI_VS_AI:
			# Show which engines are fighting — before this just said
			# "AI vs AI", which made it impossible to tell L4 vs L6
			# from L5 vs L1 at a glance.
			color_label.text = "%s (Black) vs %s (White)" % [
				_friendly_engine_name(0), _friendly_engine_name(1)
			]
			resign_button.text = "Stop"


func _update_color_label() -> void:
	# Vs-AI: say who you're playing against so the HUD doesn't just say
	# "AI" with no context.
	var opponent_idx := 1 if GameManager.my_color == _GameLogic.BLACK else 0
	var opp_name := _friendly_engine_name(opponent_idx)
	if GameManager.my_color == _GameLogic.BLACK:
		color_label.text = "You: Black \u25cf  vs  %s" % opp_name
	else:
		color_label.text = "You: White \u25cb  vs  %s" % opp_name


func _friendly_engine_name(player_idx: int) -> String:
	var p = GameManager.players[player_idx] if player_idx < GameManager.players.size() else null
	if p == null:
		return "?"
	if "ai_engine" in p and p.ai_engine != null and p.ai_engine.has_method("get_name"):
		return p.ai_engine.get_name()
	# Human / no engine: just say which side.
	return "Human" if p.player_type == _PlayerController.Type.LOCAL_HUMAN else "AI"


func _on_turn_changed(_is_my_turn: bool) -> void:
	match GameManager.mode:
		GameManager.GameMode.LOCAL_PVP:
			if GameManager.logic.current_player == _GameLogic.BLACK:
				turn_label.text = "\u25b6 Black's Turn"
			else:
				turn_label.text = "\u25b6 White's Turn"
			turn_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
		GameManager.GameMode.VS_AI:
			if _is_my_turn:
				turn_label.text = "\u25b6 Your Turn"
				turn_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
			else:
				turn_label.text = "AI Thinking..."
				turn_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
		GameManager.GameMode.AI_VS_AI:
			if GameManager.logic.current_player == _GameLogic.BLACK:
				turn_label.text = "Black AI..."
			else:
				turn_label.text = "White AI..."
			turn_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
		_:  # ONLINE
			if _is_my_turn:
				turn_label.text = "\u25b6 Your Turn"
				turn_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
			else:
				turn_label.text = "Opponent's Turn"
				turn_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))


func _on_stone_placed(_row: int, _col: int, _color: int) -> void:
	move_label.text = "Move: %d" % GameManager.logic.move_history.size()


func _on_game_ended(winner: int) -> void:
	game_over_panel.visible = true
	play_again_button.visible = true
	play_again_button.text = "Play Again"
	play_again_button.disabled = false

	match GameManager.mode:
		GameManager.GameMode.LOCAL_PVP:
			if winner == _GameLogic.EMPTY:
				result_label.text = "Draw!"
				result_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			elif winner == _GameLogic.BLACK:
				result_label.text = "Black Wins!"
				result_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
			else:
				result_label.text = "White Wins!"
				result_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
		_:  # ONLINE, VS_AI
			if winner == _GameLogic.EMPTY:
				result_label.text = "Draw!"
				result_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			elif winner == GameManager.my_color:
				result_label.text = "You Win!"
				result_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
			else:
				result_label.text = "You Lose"
				result_label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2))


func _on_game_reset() -> void:
	game_over_panel.visible = false
	reset_request_panel.visible = false
	move_label.text = "Move: 0"


func _on_resign_pressed() -> void:
	match GameManager.mode:
		GameManager.GameMode.LOCAL_PVP:
			# "New Game" — just restart
			GameManager.request_reset()
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


func _on_play_again_pressed() -> void:
	if GameManager.mode == GameManager.GameMode.ONLINE:
		play_again_button.text = "Waiting..."
		play_again_button.disabled = true
		GameManager.request_reset()
	else:
		GameManager.request_reset()


func _on_main_menu_pressed() -> void:
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
	result_label.text = "Opponent Disconnected"
	result_label.add_theme_color_override("font_color", Color.RED)
	play_again_button.visible = false
