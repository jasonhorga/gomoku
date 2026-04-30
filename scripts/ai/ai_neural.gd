extends "res://scripts/ai/ai_engine.gd"

# Level 6 AI: CoreML CNN + Swift MCTS via the GomokuNeural plugin.
#
# Before 2026-04-21 this had two fallback paths (TCP to Python
# onnx_server, then GDScript MCTS) because iOS had no plugin.
# Post-unification the plugin is available on iOS and macOS — both
# paths are gone. Linux editor gets a push_error since we no longer
# support L6 there.


func choose_move(board: Array, current_player: int, move_history: Array) -> Vector2i:
	if not Engine.has_singleton("GomokuNeural"):
		push_error("GomokuNeural plugin not available — L6 requires Swift plugin")
		return Vector2i(7, 7)

	var plugin = Engine.get_singleton("GomokuNeural")
	var last_move: Vector2i = move_history[-1] if not move_history.is_empty() else Vector2i(-1, -1)
	var result: Vector2i = plugin.get_move(6, board, current_player, last_move, forbidden_enabled)
	Log.info("Neural", "plugin L6 move=%s" % result)
	return result


func get_name() -> String:
	return "Neural(CoreML+MCTS)"
