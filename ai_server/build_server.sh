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
# Fall back to best_model.onnx (the production model checked into git)
if [ ! -f "$MODEL" ] && [ -f "data/weights/best_model.onnx" ]; then
    cp data/weights/best_model.onnx "$MODEL"
    echo "  Copied best_model.onnx → model.onnx"
fi
if [ ! -f "$MODEL" ]; then
    echo "No model.onnx or best_model.onnx found. Export first:"
    echo "  python export_onnx.py data/weights/gen_XXX.pt"
    exit 1
fi

# Use the spec file as single source of truth (bundles ai/ package for MCTS)
pyinstaller --clean --noconfirm gomoku_ai_server.spec

echo ""
echo "=== Done ==="
echo "Output: dist/gomoku_ai_server ($(du -h dist/gomoku_ai_server | cut -f1))"
echo ""
echo "Next: put it inside your .app bundle:"
echo "  cp dist/gomoku_ai_server path/to/Gomoku.app/Contents/MacOS/"
