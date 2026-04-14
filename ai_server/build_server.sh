#!/bin/bash
# Build standalone AI server and embed it into the macOS .app bundle.
# Run on MacBook after training.
#
# Prerequisites:
#   pip install pyinstaller onnxruntime numpy
#
# Usage:
#   cd gomoku/ai_server
#   ./build_server.sh
#
# After this, copy dist/gomoku_ai_server into:
#   Gomoku.app/Contents/MacOS/gomoku_ai_server
#
# Or use build_app.sh for the complete package.

set -e

echo "=== Building Gomoku AI Server ==="

python3 -c "import onnxruntime" 2>/dev/null || { echo "Run: pip install onnxruntime"; exit 1; }
python3 -c "import PyInstaller" 2>/dev/null || { echo "Run: pip install pyinstaller"; exit 1; }

MODEL="data/weights/model.onnx"
if [ ! -f "$MODEL" ]; then
    echo "No model.onnx found. Export first:"
    echo "  python export_onnx.py data/weights/gen_XXX.pt"
    exit 1
fi

pyinstaller \
    --onefile \
    --name gomoku_ai_server \
    --add-data "protocol.py:." \
    --add-data "$MODEL:." \
    --hidden-import onnxruntime \
    --clean \
    --noconfirm \
    onnx_server.py

echo ""
echo "=== Done ==="
echo "Output: dist/gomoku_ai_server ($(du -h dist/gomoku_ai_server | cut -f1))"
echo ""
echo "Next: put it inside your .app bundle:"
echo "  cp dist/gomoku_ai_server path/to/Gomoku.app/Contents/MacOS/"
