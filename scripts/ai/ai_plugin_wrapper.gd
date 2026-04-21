extends "res://scripts/ai/ai_engine.gd"

# Thin adapter: routes Godot's engine interface
# (choose_move(board, current_player, move_history)) to the
# GomokuNeural Swift plugin (get_move(level, board, player, last_move)).
#
# Replaces the old GDScript ai_mcts.gd for L5 and the GDScript/TCP
# fallback in ai_neural.gd for L6 — after 2026-04-21 unification both
# iOS and macOS share the same Swift/CoreML engine.
#
# Level is set at construction time so the same wrapper class can back
# either L5 (pattern-MCTS, 1500 sims) or L6 (hybrid CNN+MCTS, 200 sims +
# VCF/VCT). The plugin picks the right MCTSEngine config from the level.

var level: int = 5


func _init(p_level: int = 5) -> void:
	level = p_level


func choose_move(board: Array, current_player: int, move_history: Array) -> Vector2i:
	if not Engine.has_singleton("GomokuNeural"):
		push_error("GomokuNeural plugin not available (needed for L%d)" % level)
		return Vector2i(7, 7)

	var plugin = Engine.get_singleton("GomokuNeural")
	var last_move: Vector2i = move_history[-1] if not move_history.is_empty() else Vector2i(-1, -1)
	var result: Vector2i = plugin.get_move(level, board, current_player, last_move)
	Log.info("Plugin", "L%d move=%s" % [level, result])
	return result


func get_name() -> String:
	if level == 6:
		return "Neural(CoreML+MCTS)"
	return "MCTS(plugin)"
