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

# Embed AI server
cp "$SERVER" "$TMPDIR/Gomoku.app/Contents/MacOS/gomoku_ai_server"
chmod +x "$TMPDIR/Gomoku.app/Contents/MacOS/gomoku_ai_server"

# Embed model if exists
if [ -f "$ONNX_MODEL" ]; then
    cp "$ONNX_MODEL" "$TMPDIR/Gomoku.app/Contents/MacOS/model.onnx"
    echo "  Embedded model.onnx"
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
