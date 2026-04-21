#!/bin/bash
# One-step macOS .app packaging (post 2026-04-21 unification).
#
# Before: bundled Python pyinstaller binary + onnx model. Godot launched
# the subprocess via AIServerLauncher autoload and talked to it over TCP.
# .app was ~150MB because of Python + onnxruntime.
#
# After: Godot loads the GomokuNeural Swift plugin directly; CoreML
# mlmodelc is bundled as an addon resource (same path as iOS). No
# subprocess, no TCP. .app is ~15-20MB.
#
# Run on Mac after:
#   1. Plugin built: `cd ios_plugin && ./build.sh macos`
#   2. CoreML compiled: `cd ai_server && python3 export_coreml.py` →
#      produces GomokuNet.mlpackage; compile with xcrun coremlcompiler
#      to GomokuNet.mlmodelc (see macos-cd.yml step for reference)
#   3. Godot macOS export done: build/gomoku_macos.zip
#
# Usage:
#   cd gomoku
#   ./build_app.sh

set -e
cd "$(dirname "$0")"

APP_ZIP="build/gomoku_macos.zip"
OUTPUT="build/Gomoku_final.zip"

echo "=== Packaging Gomoku.app (Swift-unified) ==="

[ -f "$APP_ZIP" ] || { echo "Missing: $APP_ZIP (run Godot macOS export first)"; exit 1; }

# Extract base .app
TMPDIR=$(mktemp -d)
unzip -q "$APP_ZIP" -d "$TMPDIR"

# Find the .app bundle Godot exported (name comes from config/name,
# which may include Chinese chars/spaces) and normalize to Gomoku.app.
EXPORTED_APP=$(ls -d "$TMPDIR"/*.app | head -1)
if [ -z "$EXPORTED_APP" ]; then
    echo "No .app found in $APP_ZIP"; exit 1
fi
if [ "$(basename "$EXPORTED_APP")" != "Gomoku.app" ]; then
    mv "$EXPORTED_APP" "$TMPDIR/Gomoku.app"
fi
APP="$TMPDIR/Gomoku.app"

# Godot names the main binary after config/name too — normalize to "Gomoku"
MAIN_BIN=$(ls "$APP/Contents/MacOS/" | head -1)
if [ -n "$MAIN_BIN" ] && [ "$MAIN_BIN" != "Gomoku" ]; then
    mv "$APP/Contents/MacOS/$MAIN_BIN" "$APP/Contents/MacOS/Gomoku"
fi

# Also normalize the .pck name and CFBundleExecutable reference
MAIN_PCK=$(ls "$APP/Contents/Resources/" | grep '\.pck$' | head -1)
if [ -n "$MAIN_PCK" ] && [ "$MAIN_PCK" != "Gomoku.pck" ]; then
    mv "$APP/Contents/Resources/$MAIN_PCK" "$APP/Contents/Resources/Gomoku.pck"
fi
# Patch Info.plist CFBundleExecutable + CFBundleName + CFBundleDisplayName
if command -v plutil >/dev/null 2>&1; then
    plutil -replace CFBundleExecutable -string "Gomoku" "$APP/Contents/Info.plist"
    plutil -replace CFBundleName -string "Gomoku" "$APP/Contents/Info.plist"
    plutil -replace CFBundleDisplayName -string "五子棋 Gomoku" "$APP/Contents/Info.plist"
fi

# Godot's macOS export bundles `res://addons/gomoku_neural/` contents
# into the .app, so the plugin .dylib and .mlmodelc should already be
# present under Contents/Resources/addons/gomoku_neural/. No manual
# copying needed — just verify:
PLUGIN="$APP/Contents/Resources/addons/gomoku_neural/libgomoku_neural.macos.template_release.dylib"
MLMODEL="$APP/Contents/Resources/addons/gomoku_neural/GomokuNet.mlmodelc"
if [ ! -f "$PLUGIN" ]; then
    echo "⚠️  Plugin .dylib not found in exported .app:"
    echo "    expected: $PLUGIN"
    echo "    Did you run 'cd ios_plugin && ./build.sh macos' before Godot export?"
    echo "    And is libgomoku_neural.macos.template_release.dylib copied into addons/gomoku_neural/ ?"
    exit 1
fi
if [ ! -d "$MLMODEL" ]; then
    echo "⚠️  GomokuNet.mlmodelc not found:"
    echo "    expected: $MLMODEL"
    echo "    Compile with: xcrun coremlcompiler compile GomokuNet.mlpackage addons/gomoku_neural/"
    exit 1
fi
echo "  ✓ Plugin dylib: $(du -h "$PLUGIN" | cut -f1)"
echo "  ✓ CoreML model: $(du -sh "$MLMODEL" | cut -f1)"

# Re-package
cd "$TMPDIR"
rm -f "$OLDPWD/$OUTPUT"
zip -r -q "$OLDPWD/$OUTPUT" Gomoku.app
cd "$OLDPWD"
rm -rf "$TMPDIR"

SIZE=$(du -h "$OUTPUT" | cut -f1)
echo ""
echo "=== Done ==="
echo "Output: $OUTPUT ($SIZE)"
echo ""
echo "Users double-click Gomoku.app — everything is inside."
echo "  Level 1-4: GDScript AI"
echo "  Level 5:   Swift plugin (pattern-MCTS)"
echo "  Level 6:   Swift plugin + CoreML (hybrid CNN+MCTS)"
