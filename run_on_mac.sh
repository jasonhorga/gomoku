#!/bin/bash
# ============================================================
# Gomoku AI - 一键训练 + 打包
# 在 MacBook 上运行，跑完就有完整的 Gomoku.app
#
# 用法:
#   cd gomoku
#   chmod +x run_on_mac.sh
#   ./run_on_mac.sh
#
# 预计耗时: 2-4 小时 (10 代训练)
# ============================================================

set -e
cd "$(dirname "$0")"
PROJ_DIR="$(pwd)"

echo "============================================"
echo "  Gomoku AI Training + Packaging Pipeline"
echo "  $(date)"
echo "============================================"
echo ""

# ---------- 1. 安装依赖 ----------
echo "[1/6] Installing dependencies..."
pip3 install --break-system-packages --quiet torch numpy onnxruntime pyinstaller 2>&1 | tail -3
echo "  Done."
echo ""

# ---------- 2. 训练 ----------
echo "[2/6] Training AI (10 generations, 100 games each)..."
echo "  This will take 1-3 hours. Logs: ai_server/logs/training.log"
echo ""
cd "$PROJ_DIR/ai_server"
mkdir -p logs data/weights

python3 train_pipeline.py \
    --generations 10 \
    --games 100 \
    --simulations 200 \
    --epochs 10 \
    --eval-games 20 \
    --filters 8 \
    --blocks 1

echo ""
echo "  Training complete."
echo ""

# ---------- 3. 找到最新权重 ----------
LATEST_PT=$(ls -t data/weights/gen_*.pt 2>/dev/null | head -1)
if [ -z "$LATEST_PT" ]; then
    echo "ERROR: No weights found after training!"
    exit 1
fi
echo "[3/6] Latest weights: $LATEST_PT"

# ---------- 4. 导出 ONNX ----------
echo "[4/6] Exporting ONNX model..."
python3 export_onnx.py "$LATEST_PT" -o data/weights/model.onnx --filters 8 --blocks 1
echo ""

# ---------- 5. 打包 server ----------
echo "[5/6] Building standalone AI server..."
pyinstaller \
    --onefile \
    --name gomoku_ai_server \
    --add-data "protocol.py:." \
    --add-data "data/weights/model.onnx:." \
    --hidden-import onnxruntime \
    --clean \
    --noconfirm \
    onnx_server.py 2>&1 | tail -5

if [ ! -f "dist/gomoku_ai_server" ]; then
    echo "ERROR: PyInstaller build failed!"
    exit 1
fi
echo "  Server built: $(du -h dist/gomoku_ai_server | cut -f1)"
echo ""

# ---------- 6. 组装 .app ----------
echo "[6/6] Packaging Gomoku.app..."
cd "$PROJ_DIR"

APP_ZIP="build/gomoku_macos.zip"
if [ ! -f "$APP_ZIP" ]; then
    echo "ERROR: $APP_ZIP not found! Compile on Linux first."
    exit 1
fi

TMPDIR=$(mktemp -d)
unzip -q "$APP_ZIP" -d "$TMPDIR"

# 嵌入 AI server
cp "ai_server/dist/gomoku_ai_server" "$TMPDIR/Gomoku.app/Contents/MacOS/"
chmod +x "$TMPDIR/Gomoku.app/Contents/MacOS/gomoku_ai_server"

# 嵌入模型
if [ -f "ai_server/data/weights/model.onnx" ]; then
    cp "ai_server/data/weights/model.onnx" "$TMPDIR/Gomoku.app/Contents/MacOS/"
fi

# 打包
OUTPUT="build/Gomoku_final.zip"
cd "$TMPDIR"
zip -r -q "$PROJ_DIR/$OUTPUT" Gomoku.app
cd "$PROJ_DIR"
rm -rf "$TMPDIR"

echo ""
echo "============================================"
echo "  ALL DONE! $(date)"
echo "============================================"
echo ""
echo "  Output: $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
echo "  Training log: ai_server/logs/training.log"
echo ""
echo "  解压 $OUTPUT 双击 Gomoku.app 即可游玩"
echo "  Level 1-5: 内置 AI"
echo "  Level 6: 神经网络 AI (自动启动)"
echo "============================================"
