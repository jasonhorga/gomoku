#!/bin/bash
# Export big_iter_1.pt (128f/6b, verified 66.9% vs bootstrap) to ONNX
# for use in the Godot game.
set -e
cd "$(dirname "$0")/ai_server"

python3 -m pip install -q --break-system-packages onnx onnxscript

python3 export_onnx.py data/weights/big_iter_1.pt \
    -o data/weights/model.onnx \
    --filters 128 --blocks 6 --input-channels 9

echo ""
echo "Output:"
ls -la data/weights/model.onnx
