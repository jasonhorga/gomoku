#!/usr/bin/env bash
# Build the GomokuNeural plugin for iOS and/or macOS as GDExtension.
#
# Depends on godot-cpp (cloned into ./godot-cpp by CI). For each slice:
#   1. Build godot-cpp's static lib via its own SCons.
#   2. Compile Swift (*.swift) to a static lib + emit ObjC interface header.
#   3. Compile our C++/Obj-C++ with godot-cpp headers + the Swift header.
#   4. iOS: libtool-combine into static .a; xcodebuild assembles xcframework.
#      macOS: clang++ -dynamiclib links everything into a single .dylib.
#
# Usage:
#   ./build.sh                   # iOS only (back-compat default)
#   ./build.sh ios               # iOS only
#   ./build.sh macos             # macOS only
#   ./build.sh ios macos         # both (or: PLATFORMS="ios macos" ./build.sh)
#
# Env (optional):
#   GODOT_CPP_DIR  — path to godot-cpp checkout (default ./godot-cpp)
#   OUTPUT_DIR     — build output root (default ./build)
#   TARGET         — template_release | template_debug (default template_release)
#   IOS_MIN        — min iOS deployment target (default 15.4)
#   MACOS_MIN      — min macOS deployment target (default 13.0)

set -euo pipefail
cd "$(dirname "$0")"

GODOT_CPP_DIR="${GODOT_CPP_DIR:-./godot-cpp}"
OUTPUT_DIR="${OUTPUT_DIR:-./build}"
TARGET="${TARGET:-template_release}"
IOS_MIN="${IOS_MIN:-15.4}"
MACOS_MIN="${MACOS_MIN:-13.0}"

# Positional args override PLATFORMS env; default to iOS for backwards compat.
if [ $# -gt 0 ]; then
	PLATFORMS="$*"
else
	PLATFORMS="${PLATFORMS:-ios}"
fi

if [ ! -d "$GODOT_CPP_DIR/include" ]; then
	echo "❌ GODOT_CPP_DIR=$GODOT_CPP_DIR has no include/ — clone godot-cpp first."
	exit 1
fi

mkdir -p "$OUTPUT_DIR"

# Install scons if missing (CI needs this; local Mac usually has it via brew).
if ! command -v scons >/dev/null 2>&1; then
	python3 -m pip install --quiet scons
fi

# ---------------------------------------------------------------------- iOS

build_ios_slice() {
	local arch="$1"             # arm64 | universal
	local sdk_name="$2"         # iphoneos | iphonesimulator
	local tgt_suffix="$3"       # "" | "-simulator"
	local sim_flag="$4"         # "" | ".simulator"
	local slice="$OUTPUT_DIR/${sdk_name}"
	local sdk_path
	sdk_path=$(xcrun --sdk "$sdk_name" --show-sdk-path)

	echo "=== iOS slice: $sdk_name ($arch$tgt_suffix) ==="
	mkdir -p "$slice"

	local target="arm64-apple-ios${IOS_MIN}${tgt_suffix}"
	# swiftc wants the exact simulator/device target; for universal sim
	# we still emit arm64 here (the CI runner is Apple Silicon; the
	# simulator slice is Apple Silicon only — fine for our use).

	# -runtime-compatibility-version none stops swiftc from emitting the
	# autolink hint for libswiftCompatibility56. Godot's exported xcodeproj
	# doesn't link Swift runtime libs, so the hint ends up unresolved at
	# archive. Our Swift surface (NSObject/@objc wrapper, NSNumber/CGPoint
	# bridging, Int8 arrays, Double math) touches none of the features the
	# shim provides.
	xcrun swiftc \
		-target "$target" \
		-sdk "$sdk_path" \
		-module-name GomokuMLCore \
		-emit-module \
		-emit-module-path "$slice/GomokuMLCore.swiftmodule" \
		-emit-objc-header \
		-emit-objc-header-path "$slice/GomokuMLCore-Swift.h" \
		-emit-library -static \
		-parse-as-library \
		-runtime-compatibility-version none \
		-O \
		-o "$slice/libGomokuMLCore.a" \
		Sources/GomokuMLCore.swift \
		Sources/GameLogic.swift \
		Sources/PatternEval.swift \
		Sources/VcfSearch.swift \
		Sources/VctSearch.swift \
		Sources/MCTSEngine.swift \
		Sources/CoreMLAdapter.swift

	local cxx_flags=(
		-target "$target"
		-isysroot "$sdk_path"
		-I "$GODOT_CPP_DIR/include"
		-I "$GODOT_CPP_DIR/gen/include"
		-I "$GODOT_CPP_DIR/gdextension"
		-I "$slice"
		-std=gnu++17
		-fno-exceptions -fvisibility=hidden
		-DNDEBUG -DNS_BLOCK_ASSERTIONS=1
		-O2
	)

	xcrun clang++ -c Sources/gomoku_neural.mm \
		"${cxx_flags[@]}" \
		-fobjc-arc -fmodules \
		-o "$slice/gomoku_neural.o"

	xcrun clang++ -c Sources/register_types.cpp \
		"${cxx_flags[@]}" \
		-o "$slice/register_types.o"

	local slice_lib="$OUTPUT_DIR/libgomoku_neural.ios.${TARGET}${sim_flag}.a"
	xcrun libtool -static \
		-o "$slice_lib" \
		"$slice/libGomokuMLCore.a" \
		"$slice/gomoku_neural.o" \
		"$slice/register_types.o"
	echo "Wrote: $slice_lib"
}

build_ios() {
	echo "=== iOS: godot-cpp (device + simulator) ==="

	if [ ! -f "$GODOT_CPP_DIR/bin/libgodot-cpp.ios.${TARGET}.arm64.a" ]; then
		(cd "$GODOT_CPP_DIR" && scons platform=ios arch=arm64 ios_simulator=no target="$TARGET")
	fi

	if [ ! -f "$GODOT_CPP_DIR/bin/libgodot-cpp.ios.${TARGET}.universal.simulator.a" ]; then
		(cd "$GODOT_CPP_DIR" && scons platform=ios arch=universal ios_simulator=yes target="$TARGET")
	fi

	build_ios_slice arm64 iphoneos "" ""
	build_ios_slice universal iphonesimulator "-simulator" ".simulator"

	echo "=== iOS: xcframeworks ==="
	rm -rf "$OUTPUT_DIR/libgomoku_neural.ios.${TARGET}.xcframework"
	xcodebuild -create-xcframework \
		-library "$OUTPUT_DIR/libgomoku_neural.ios.${TARGET}.a" \
		-library "$OUTPUT_DIR/libgomoku_neural.ios.${TARGET}.simulator.a" \
		-output "$OUTPUT_DIR/libgomoku_neural.ios.${TARGET}.xcframework"

	rm -rf "$OUTPUT_DIR/libgodot-cpp.ios.${TARGET}.xcframework"
	xcodebuild -create-xcframework \
		-library "$GODOT_CPP_DIR/bin/libgodot-cpp.ios.${TARGET}.arm64.a" \
		-library "$GODOT_CPP_DIR/bin/libgodot-cpp.ios.${TARGET}.universal.simulator.a" \
		-output "$OUTPUT_DIR/libgodot-cpp.ios.${TARGET}.xcframework"

	echo ""
	du -sh "$OUTPUT_DIR/libgomoku_neural.ios.${TARGET}.xcframework"
	du -sh "$OUTPUT_DIR/libgodot-cpp.ios.${TARGET}.xcframework"
}

# ---------------------------------------------------------------------- macOS

build_macos() {
	echo "=== macOS: godot-cpp (arm64) ==="
	# macOS GDExtension is a .dylib loaded at runtime. godot-cpp is still
	# static (linked INTO our dylib) so end-user Godot only has to load
	# one binary. arm64-only for now — user is on M-chip. Intel added
	# later if needed.
	if [ ! -f "$GODOT_CPP_DIR/bin/libgodot-cpp.macos.${TARGET}.arm64.a" ]; then
		(cd "$GODOT_CPP_DIR" && scons platform=macos arch=arm64 target="$TARGET")
	fi

	local slice="$OUTPUT_DIR/macos"
	mkdir -p "$slice"
	local sdk_path
	sdk_path=$(xcrun --sdk macosx --show-sdk-path)
	local target="arm64-apple-macos${MACOS_MIN}"

	echo "=== macOS: Swift → static lib + ObjC header ==="
	xcrun swiftc \
		-target "$target" \
		-sdk "$sdk_path" \
		-module-name GomokuMLCore \
		-emit-module \
		-emit-module-path "$slice/GomokuMLCore.swiftmodule" \
		-emit-objc-header \
		-emit-objc-header-path "$slice/GomokuMLCore-Swift.h" \
		-emit-library -static \
		-parse-as-library \
		-runtime-compatibility-version none \
		-O \
		-o "$slice/libGomokuMLCore.a" \
		Sources/GomokuMLCore.swift \
		Sources/GameLogic.swift \
		Sources/PatternEval.swift \
		Sources/VcfSearch.swift \
		Sources/VctSearch.swift \
		Sources/MCTSEngine.swift \
		Sources/CoreMLAdapter.swift

	echo "=== macOS: C++/Obj-C++ → .o ==="
	local cxx_flags=(
		-target "$target"
		-isysroot "$sdk_path"
		-I "$GODOT_CPP_DIR/include"
		-I "$GODOT_CPP_DIR/gen/include"
		-I "$GODOT_CPP_DIR/gdextension"
		-I "$slice"
		-std=gnu++17
		-fno-exceptions -fvisibility=hidden
		-DNDEBUG -DNS_BLOCK_ASSERTIONS=1
		-O2
	)

	xcrun clang++ -c Sources/gomoku_neural.mm \
		"${cxx_flags[@]}" \
		-fobjc-arc -fmodules \
		-o "$slice/gomoku_neural.o"

	xcrun clang++ -c Sources/register_types.cpp \
		"${cxx_flags[@]}" \
		-o "$slice/register_types.o"

	echo "=== macOS: link → .dylib ==="
	# -all_load pulls every @objc symbol from the Swift static lib so
	# GDCLASS registration (via Swift class emission) actually shows up
	# at runtime. Without it the linker strips "unused" symbols and the
	# singleton registration vanishes.
	#
	# Frameworks linked: CoreML for CoreMLAdapter, Foundation for
	# NSArray/NSNumber bridging, CoreGraphics for CGPoint return type.
	# Swift runtime is in /usr/lib on macOS 13+, -runtime-compatibility-
	# version none opts us out of shim linking.
	local dylib="$OUTPUT_DIR/libgomoku_neural.macos.${TARGET}.dylib"
	xcrun clang++ -dynamiclib \
		-target "$target" \
		-isysroot "$sdk_path" \
		-install_name "@rpath/libgomoku_neural.macos.${TARGET}.dylib" \
		-framework CoreML \
		-framework Foundation \
		-framework CoreGraphics \
		-Wl,-all_load \
		-o "$dylib" \
		"$slice/libGomokuMLCore.a" \
		"$slice/gomoku_neural.o" \
		"$slice/register_types.o" \
		"$GODOT_CPP_DIR/bin/libgodot-cpp.macos.${TARGET}.arm64.a"

	echo "Wrote: $dylib"
	file "$dylib" | head -2
	otool -L "$dylib" | head -10
	du -sh "$dylib"
}

# ---------------------------------------------------------------------- dispatch

for p in $PLATFORMS; do
	case "$p" in
		ios) build_ios ;;
		macos) build_macos ;;
		*) echo "❌ Unknown platform: $p (expected ios | macos)"; exit 1 ;;
	esac
done

# Canonical .gdextension lives in addons/gomoku_neural/; pull it into
# the build output so the artifact is self-contained (plugin-build.yml
# is a standalone sanity check, not the full Godot integration path).
cp ../addons/gomoku_neural/gomoku_neural.gdextension "$OUTPUT_DIR/"

echo ""
echo "✅ Plugin build complete (platforms: $PLATFORMS):"
ls -la "$OUTPUT_DIR/" | grep -v '^d' | head -20
