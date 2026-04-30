#ifndef GOMOKU_NEURAL_H
#define GOMOKU_NEURAL_H

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace godot {

// GDExtension-exposed class. GDScript accesses it via
// `Engine.get_singleton("GomokuNeural")`.
//
// All ML logic lives in Swift (GomokuMLCore.swift); this class is a
// thin Obj-C++ bridge — hence gomoku_neural.mm not .cpp.
class GomokuNeural : public Object {
	GDCLASS(GomokuNeural, Object)

	static GomokuNeural *instance;

protected:
	static void _bind_methods();

public:
	static GomokuNeural *get_singleton();

	GomokuNeural();
	~GomokuNeural();

	// P2b hello API: ignores inputs, returns hardcoded (7, 7) via Swift.
	// Grows into the full L5/L6 surface in P2f.
	Vector2i get_move(int level, Array board, int player, Vector2i last_move, bool forbidden_enabled);
	String plugin_version();
};

} // namespace godot

#endif // GOMOKU_NEURAL_H
