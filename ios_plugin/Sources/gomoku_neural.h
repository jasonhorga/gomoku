#ifndef GOMOKU_NEURAL_H
#define GOMOKU_NEURAL_H

#include "core/version.h"

#if VERSION_MAJOR == 4
#include "core/object/class_db.h"
#else
#error "GomokuNeural plugin requires Godot 4.x headers"
#endif

// GDCLASS subclass exposed to GDScript as `Engine.get_singleton("GomokuNeural")`.
// Thin Obj-C++ wrapper over the Swift core; all ML logic lives in Swift.
class GomokuNeural : public Object {

	GDCLASS(GomokuNeural, Object);

	static GomokuNeural *instance;

protected:
	static void _bind_methods();

public:
	static GomokuNeural *get_singleton();

	GomokuNeural();
	~GomokuNeural();

	// P2b hello-world API — returns (7,7) via Swift, ignoring inputs.
	// Will grow into the full L5/L6 interface in P2f.
	Vector2i get_move(int level, Array board, int player, Vector2i last_move);
	String plugin_version();
};

#endif // GOMOKU_NEURAL_H
