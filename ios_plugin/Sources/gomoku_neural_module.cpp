#include "gomoku_neural_module.h"

#include "core/version.h"

#if VERSION_MAJOR == 4
#include "core/config/engine.h"
#else
#error "Requires Godot 4.x"
#endif

#include "gomoku_neural.h"

GomokuNeural *gomoku_neural_ptr = nullptr;

void register_gomoku_neural_types() {
	gomoku_neural_ptr = memnew(GomokuNeural);
	Engine::get_singleton()->add_singleton(
			Engine::Singleton("GomokuNeural", gomoku_neural_ptr));
}

void unregister_gomoku_neural_types() {
	if (gomoku_neural_ptr) {
		memdelete(gomoku_neural_ptr);
		gomoku_neural_ptr = nullptr;
	}
}
