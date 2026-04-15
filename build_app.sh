#!/bin/bash
# One-step macOS .app packaging.
# Run on MacBook after:
#   1. Training is done (ai_server/data/weights/gen_XXX.pt exists)
#   2. ONNX export is done (ai_server/data/weights/model.onnx exists)
#   3. AI server is built (ai_server/dist/gomoku_ai_server exists)
#   4. Godot .app base exists (build/gomoku_macos.zip)
#
# Usage:
#   cd gomoku
#   ./build_app.sh

set -e
cd "$(dirname "$0")"

APP_ZIP="build/gomoku_macos.zip"
SERVER="ai_server/dist/gomoku_ai_server"
ONNX_MODEL="ai_server/data/weights/model.onnx"
OUTPUT="build/Gomoku_final.zip"

echo "=== Packaging Gomoku.app ==="

# Check files
[ -f "$APP_ZIP" ] || { echo "Missing: $APP_ZIP (compile on Linux first)"; exit 1; }
[ -f "$SERVER" ] || { echo "Missing: $SERVER (run ai_server/build_server.sh first)"; exit 1; }

# Extract base .app
TMPDIR=$(mktemp -d)
unzip -q "$APP_ZIP" -d "$TMPDIR"

# Find the .app bundle Godot exported (name comes from config/name,
# which may include Chinese chars/spaces) and normalize to Gomoku.app
EXPORTED_APP=$(ls -d "$TMPDIR"/*.app | head -1)
if [ -z "$EXPORTED_APP" ]; then
    echo "No .app found in $APP_ZIP"; exit 1
fi
if [ "$(basename "$EXPORTED_APP")" != "Gomoku.app" ]; then
    mv "$EXPORTED_APP" "$TMPDIR/Gomoku.app"
fi
APP="$TMPDIR/Gomoku.app"

# Godot names the main binary after config/name too — normalize to "Gomoku"
MAIN_BIN=$(ls "$APP/Contents/MacOS/" | grep -v '^gomoku_ai_server$\|^model\.onnx$' | head -1)
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

# Embed AI server
cp "$SERVER" "$APP/Contents/MacOS/gomoku_ai_server"
chmod +x "$APP/Contents/MacOS/gomoku_ai_server"

# Embed model in Resources/ (not MacOS/ — codesign rejects non-Mach-O files there)
if [ -f "$ONNX_MODEL" ]; then
    cp "$ONNX_MODEL" "$APP/Contents/Resources/model.onnx"
    echo "  Embedded model.onnx (Resources/)"
fi

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
echo "Users just double-click Gomoku.app — everything is inside."
echo "  Level 1-5: built-in GDScript AI"
echo "  Level 6: auto-launches embedded neural network server"
