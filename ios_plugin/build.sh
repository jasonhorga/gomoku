#!/usr/bin/env bash
# Build the GomokuNeural plugin for iOS as GDExtension + xcframework.
#
# Depends on godot-cpp (cloned into ./godot-cpp by CI). For each iOS
# slice we:
#   1. Build godot-cpp's static lib via its own SCons — this handles all
#      the generated-header machinery the godot-ios-plugins route was
#      fighting. Outputs into godot-cpp/bin/.
#   2. Compile Swift (GomokuMLCore.swift) to a static lib + emit an
#      Obj-C interface header.
#   3. Compile our C++/Obj-C++ with godot-cpp headers + the Swift header.
#   4. libtool-combine Swift + our .o files into a single libgomoku_neural
#      static archive.
# Then xcodebuild -create-xcframework assembles both slices of both the
# plugin and godot-cpp into the two xcframeworks referenced from
# gomoku_neural.gdextension.
#
# Env (optional):
#   GODOT_CPP_DIR  — path to godot-cpp checkout (default ./godot-cpp)
#   OUTPUT_DIR     — build output root (default ./build)
#   TARGET         — template_release | template_debug (default template_release)
#   IOS_MIN        — min iOS deployment target (default 15.0)

set -euo pipefail
cd "$(dirname "$0")"

GODOT_CPP_DIR="${GODOT_CPP_DIR:-./godot-cpp}"
OUTPUT_DIR="${OUTPUT_DIR:-./build}"
TARGET="${TARGET:-template_release}"
IOS_MIN="${IOS_MIN:-15.0}"

if [ ! -d "$GODOT_CPP_DIR/include" ]; then
	echo "❌ GODOT_CPP_DIR=$GODOT_CPP_DIR has no include/ — clone godot-cpp first."
	exit 1
fi

mkdir -p "$OUTPUT_DIR"

# Install scons if missing (CI needs this; local Mac usually has it via brew).
if ! command -v scons >/dev/null 2>&1; then
	python3 -m pip install --quiet scons
fi

echo "=== Phase 1: Build godot-cpp static libs (device + simulator) ==="

# godot-cpp test example pattern: arch=arm64 for device, arch=universal
# for simulator (runs on both Intel and Apple Silicon sim).
if [ ! -f "$GODOT_CPP_DIR/bin/libgodot-cpp.ios.${TARGET}.arm64.a" ]; then
	(cd "$GODOT_CPP_DIR" && scons platform=ios arch=arm64 ios_simulator=no target="$TARGET")
fi

if [ ! -f "$GODOT_CPP_DIR/bin/libgodot-cpp.ios.${TARGET}.universal.simulator.a" ]; then
	(cd "$GODOT_CPP_DIR" && scons platform=ios arch=universal ios_simulator=yes target="$TARGET")
fi

ls -la "$GODOT_CPP_DIR/bin/" | grep -i ios

build_slice() {
	local arch="$1"             # arm64 | universal
	local sdk_name="$2"         # iphoneos | iphonesimulator
	local tgt_suffix="$3"       # "" | "-simulator"
	local sim_flag="$4"         # "" | ".simulator"
	local slice="$OUTPUT_DIR/${sdk_name}"
	local sdk_path
	sdk_path=$(xcrun --sdk "$sdk_name" --show-sdk-path)

	echo "=== Phase 2-4: Build our plugin slice: $sdk_name ($arch$tgt_suffix) ==="
	mkdir -p "$slice"

	local target="arm64-apple-ios${IOS_MIN}${tgt_suffix}"
	# swiftc wants the exact simulator/device target; for universal sim
	# we still emit arm64 here (the CI runner is Apple Silicon; the
	# simulator slice is Apple Silicon only — fine for our use).

	# Phase 2: Swift → static lib + ObjC interface header.
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
		-O \
		-o "$slice/libGomokuMLCore.a" \
		Sources/GomokuMLCore.swift

	# Phase 3: C++/Obj-C++ compile against godot-cpp headers + Swift header.
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

	# Phase 4: Combine Swift + our .o into one static lib.
	# Naming matches godot-cpp test convention so the xcframework step
	# can assemble slices cleanly.
	local slice_lib="$OUTPUT_DIR/libgomoku_neural.ios.${TARGET}${sim_flag}.a"
	xcrun libtool -static \
		-o "$slice_lib" \
		"$slice/libGomokuMLCore.a" \
		"$slice/gomoku_neural.o" \
		"$slice/register_types.o"
	echo "Wrote: $slice_lib"
}

build_slice arm64 iphoneos "" ""
build_slice universal iphonesimulator "-simulator" ".simulator"

echo "=== Phase 5: Package xcframeworks ==="

# Our plugin xcframework
rm -rf "$OUTPUT_DIR/libgomoku_neural.ios.${TARGET}.xcframework"
xcodebuild -create-xcframework \
	-library "$OUTPUT_DIR/libgomoku_neural.ios.${TARGET}.a" \
	-library "$OUTPUT_DIR/libgomoku_neural.ios.${TARGET}.simulator.a" \
	-output "$OUTPUT_DIR/libgomoku_neural.ios.${TARGET}.xcframework"

# godot-cpp xcframework (the .gdextension references both)
rm -rf "$OUTPUT_DIR/libgodot-cpp.ios.${TARGET}.xcframework"
xcodebuild -create-xcframework \
	-library "$GODOT_CPP_DIR/bin/libgodot-cpp.ios.${TARGET}.arm64.a" \
	-library "$GODOT_CPP_DIR/bin/libgodot-cpp.ios.${TARGET}.universal.simulator.a" \
	-output "$OUTPUT_DIR/libgodot-cpp.ios.${TARGET}.xcframework"

# Canonical .gdextension lives in addons/gomoku_neural/; pull it into
# the build output so the artifact is self-contained (plugin-build.yml
# is a standalone sanity check, not the full Godot integration path).
cp ../addons/gomoku_neural/gomoku_neural.gdextension "$OUTPUT_DIR/"

echo ""
echo "✅ Plugin build complete:"
ls -la "$OUTPUT_DIR/" | grep -v '^d' | head -20
du -sh "$OUTPUT_DIR/libgomoku_neural.ios.${TARGET}.xcframework"
du -sh "$OUTPUT_DIR/libgodot-cpp.ios.${TARGET}.xcframework"
