#include "gomoku_neural.h"

// Swift → Obj-C interface header is emitted by swiftc at build time
// (see build.sh: -emit-objc-header-path). Its contents turn the @objc
// Swift methods into Obj-C selectors we can call from this .mm file.
#import "GomokuMLCore-Swift.h"

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

Vector2i GomokuNeural::get_move(int level, Array board, int player, Vector2i last_move) {
	GomokuMLCore *core = [[GomokuMLCore alloc] init];
	CGPoint pt = [core predictWithLevel:(NSInteger)level];
	return Vector2i((int)pt.x, (int)pt.y);
}

String GomokuNeural::plugin_version() {
	GomokuMLCore *core = [[GomokuMLCore alloc] init];
	NSString *v = [core version];
	const char *utf8 = [v UTF8String];
	return String::utf8(utf8 ? utf8 : "unknown");
}
