extends "res://scripts/player/player_controller.gd"

var ai_engine  # AIEngine instance
var _thread: Thread = null
var _cancelled: bool = false


func _init(engine = null) -> void:
	player_type = Type.LOCAL_AI
	ai_engine = engine


func request_move(board: Array, current_player: int, move_history: Array) -> void:
	_cancelled = false
	# Deep copy the board so AI search doesn't affect display state
	var board_copy: Array = []
	for row in board:
		board_copy.append(row.duplicate())

	_thread = Thread.new()
	_thread.start(_compute_move.bind(board_copy, current_player, move_history.duplicate()))


func _compute_move(board: Array, current_player: int, move_history: Array) -> void:
	# P2n: observability + defense. Two iOS builds failed to narrow down
	# "white returns (0,0) forever" because logs inside engine.choose_move
	# never fired — meaning the engine wasn't the one we expected. Log
	# what we actually have here (thread entry, runs regardless of engine
	# bugs) and never ship an invalid move to game_logic.
	var engine_desc: String = "null"
	var has_cm: bool = false
	if ai_engine != null:
		has_cm = ai_engine.has_method("choose_move")
		var script = ai_engine.get_script() if ai_engine.has_method("get_script") else null
		if script != null:
			engine_desc = str(script.resource_path)
		else:
			engine_desc = str(ai_engine)
	Log.info("LocalAI", "_compute_move engine=%s has_choose=%s player=%d" % [
		engine_desc, has_cm, current_player
	])

	var move: Vector2i = Vector2i(-1, -1)
	if ai_engine != null and has_cm:
		move = ai_engine.choose_move(board, current_player, move_history)
	else:
		Log.error("LocalAI", "ai_engine invalid (null or no choose_move), picking fallback")

	# Validate: cell in-bounds AND unoccupied. An engine that returns
	# (0,0) on a non-empty board triggered the "AI stuck" retry loop
	# until we gave up — now we just pick a legal cell ourselves.
	if move.x < 0 or move.y < 0 or move.x >= 15 or move.y >= 15 \
			or board[move.x][move.y] != 0:
		Log.warn("LocalAI", "engine returned invalid %s; scanning for legal fallback" % move)
		move = _scan_legal_fallback(board)

	if not _cancelled:
		_emit_move.call_deferred(move.x, move.y)


func _scan_legal_fallback(board: Array) -> Vector2i:
	# Prefer cells near an existing stone (center-ish play) over raw
	# row-major first-empty — the latter causes the "upper-left march"
	# symptom the user has seen twice.
	for radius in [1, 2, 3]:
		for r in range(15):
			for c in range(15):
				if board[r][c] != 0:
					continue
				# check any stone within `radius`
				for dr in range(-radius, radius + 1):
					for dc in range(-radius, radius + 1):
						var rr: int = r + dr
						var cc: int = c + dc
						if rr < 0 or rr >= 15 or cc < 0 or cc >= 15:
							continue
						if board[rr][cc] != 0:
							return Vector2i(r, c)
	# Truly empty board → center.
	return Vector2i(7, 7)


func _emit_move(row: int, col: int) -> void:
	move_decided.emit(row, col)


func cancel() -> void:
	_cancelled = true
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
