#include "gomoku_neural.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>

// Swift → Obj-C interface header emitted by swiftc at build time.
// build.sh writes it alongside libGomokuMLCore.a in the per-arch out dir
// and passes -I <out_dir> to clang++ so this #import resolves.
#import "GomokuMLCore-Swift.h"

using namespace godot;

GomokuNeural *GomokuNeural::instance = nullptr;

GomokuNeural *GomokuNeural::get_singleton() {
	return instance;
}

GomokuNeural::GomokuNeural() {
	instance = this;
}

GomokuNeural::~GomokuNeural() {
	if (instance == this) {
		instance = nullptr;
	}
}

void GomokuNeural::_bind_methods() {
	ClassDB::bind_method(
			D_METHOD("get_move", "level", "board", "player", "last_move"),
			&GomokuNeural::get_move);
	ClassDB::bind_method(
			D_METHOD("plugin_version"), &GomokuNeural::plugin_version);
}

Vector2i GomokuNeural::get_move(int level, Array board, int player, Vector2i /*last_move*/) {
	// Godot Array of Arrays → NSArray of NSArray of NSNumber so the
	// Swift @objc method can consume it directly. 15×15 board has 225
	// ints — trivial allocation.
	NSMutableArray *ns_board = [NSMutableArray arrayWithCapacity:15];
	for (int r = 0; r < 15; r++) {
		NSMutableArray *ns_row = [NSMutableArray arrayWithCapacity:15];
		Variant vrow = r < (int)board.size() ? board[r] : Variant();
		Array row = vrow.operator Array();
		for (int c = 0; c < 15; c++) {
			int v = c < (int)row.size() ? (int)row[c] : 0;
			[ns_row addObject:@(v)];
		}
		[ns_board addObject:ns_row];
	}

	GomokuMLCore *core = [[GomokuMLCore alloc] init];
	CGPoint pt = [core chooseMoveWithLevel:(NSInteger)level
	                                  board:ns_board
	                                 player:(NSInteger)player];
	return Vector2i((int)pt.x, (int)pt.y);
}

String GomokuNeural::plugin_version() {
	GomokuMLCore *core = [[GomokuMLCore alloc] init];
	NSString *v = [core version];
	const char *utf8 = [v UTF8String];
	return String::utf8(utf8 ? utf8 : "unknown");
}
