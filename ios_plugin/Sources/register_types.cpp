#include "register_types.h"

#include <gdextension_interface.h>

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "gomoku_neural.h"

using namespace godot;

void initialize_gomoku_neural_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(GomokuNeural);

	// Register as engine singleton so GDScript can do
	// Engine.get_singleton("GomokuNeural").get_move(...).
	GomokuNeural *singleton = memnew(GomokuNeural);
	Engine::get_singleton()->register_singleton("GomokuNeural", singleton);
}

void uninitialize_gomoku_neural_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GomokuNeural *singleton = GomokuNeural::get_singleton();
	if (singleton != nullptr) {
		Engine::get_singleton()->unregister_singleton("GomokuNeural");
		memdelete(singleton);
	}
}

// GDExtension entry point. The function name matches entry_symbol in
// gomoku_neural.gdextension.
extern "C" {
GDExtensionBool GDE_EXPORT gomoku_neural_library_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(
			p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_gomoku_neural_module);
	init_obj.register_terminator(uninitialize_gomoku_neural_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
