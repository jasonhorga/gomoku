#!/usr/bin/env bash
# Build the GomokuNeural iOS plugin as an xcframework.
#
# Inputs (env vars, all optional):
#   GODOT_DIR    — path to a Godot source checkout (defaults to ./godot)
#   OUTPUT_DIR   — where to write built artifacts (defaults to ./build)
#   IOS_MIN      — minimum iOS deployment target (defaults to 15.0)
#
# Output:
#   $OUTPUT_DIR/gomoku_neural.xcframework   (with ios-arm64 + ios-arm64-sim slices)
#   $OUTPUT_DIR/gomoku_neural.gdip          (copied alongside for convenience)
#
# CI-only — requires macOS + Xcode. Do not run on Linux.

set -euo pipefail

cd "$(dirname "$0")"

GODOT_DIR="${GODOT_DIR:-./godot}"
OUTPUT_DIR="${OUTPUT_DIR:-./build}"
IOS_MIN="${IOS_MIN:-15.0}"

if [ ! -d "$GODOT_DIR/core" ]; then
	echo "❌ GODOT_DIR=$GODOT_DIR does not contain core/ — clone godot source first."
	exit 1
fi

mkdir -p "$OUTPUT_DIR"

# Compile both device + simulator slices. Godot iOS export refuses
# xcframeworks that don't include a simulator slice even if the final
# app is device-only — it looks for both at ipaship time.
compile_slice() {
	local arch="$1"            # arm64
	local sdk_name="$2"        # iphoneos | iphonesimulator
	local tgt_suffix="$3"      # empty for device, "-simulator" for sim
	local out_dir="$OUTPUT_DIR/$sdk_name"
	local sdk_path
	sdk_path=$(xcrun --sdk "$sdk_name" --show-sdk-path)
	local target="${arch}-apple-ios${IOS_MIN}${tgt_suffix}"

	echo "=== Building slice: $sdk_name ($target) ==="
	mkdir -p "$out_dir"

	# 1. Swift → static lib + auto-generated Obj-C interface header.
	#    -parse-as-library: no main() required.
	#    -static: emit a .a instead of .dylib.
	xcrun swiftc \
		-target "$target" \
		-sdk "$sdk_path" \
		-module-name GomokuMLCore \
		-emit-module \
		-emit-module-path "$out_dir/GomokuMLCore.swiftmodule" \
		-emit-objc-header \
		-emit-objc-header-path "$out_dir/GomokuMLCore-Swift.h" \
		-emit-library -static \
		-parse-as-library \
		-O \
		-o "$out_dir/libGomokuMLCore.a" \
		Sources/GomokuMLCore.swift

	# 2. Obj-C++ wrapper — needs godot headers + Swift-generated header.
	xcrun clang++ -c Sources/gomoku_neural.mm \
		-target "$target" \
		-isysroot "$sdk_path" \
		-I "$GODOT_DIR" \
		-I "$GODOT_DIR/platform/ios" \
		-I "$out_dir" \
		-fobjc-arc -fmodules \
		-std=gnu++17 \
		-DIOS_ENABLED -DUNIX_ENABLED -DVULKAN_ENABLED \
		-DNDEBUG -DNS_BLOCK_ASSERTIONS=1 \
		-Wno-ambiguous-macro \
		-fno-exceptions -fvisibility=hidden \
		-O2 \
		-o "$out_dir/gomoku_neural.o"

	# 3. Plain C++ — register_types hook. No Swift header needed.
	xcrun clang++ -c Sources/gomoku_neural_module.cpp \
		-target "$target" \
		-isysroot "$sdk_path" \
		-I "$GODOT_DIR" \
		-I "$GODOT_DIR/platform/ios" \
		-std=gnu++17 \
		-DIOS_ENABLED -DUNIX_ENABLED -DVULKAN_ENABLED \
		-DNDEBUG -DNS_BLOCK_ASSERTIONS=1 \
		-Wno-ambiguous-macro \
		-fno-exceptions -fvisibility=hidden \
		-O2 \
		-o "$out_dir/gomoku_neural_module.o"

	# 4. Bundle Swift lib + both Obj-C++ objects into a single .a.
	xcrun libtool -static \
		-o "$out_dir/libgomoku_neural.a" \
		"$out_dir/libGomokuMLCore.a" \
		"$out_dir/gomoku_neural.o" \
		"$out_dir/gomoku_neural_module.o"

	ls -la "$out_dir/"
}

compile_slice arm64 iphoneos ""
compile_slice arm64 iphonesimulator "-simulator"

echo "=== Creating xcframework ==="
rm -rf "$OUTPUT_DIR/gomoku_neural.xcframework"
xcodebuild -create-xcframework \
	-library "$OUTPUT_DIR/iphoneos/libgomoku_neural.a" \
	-library "$OUTPUT_DIR/iphonesimulator/libgomoku_neural.a" \
	-output "$OUTPUT_DIR/gomoku_neural.xcframework"

cp gomoku_neural.gdip "$OUTPUT_DIR/gomoku_neural.gdip"

echo ""
echo "✅ Plugin build complete:"
find "$OUTPUT_DIR/gomoku_neural.xcframework" -type f | head -20
du -sh "$OUTPUT_DIR/gomoku_neural.xcframework"
