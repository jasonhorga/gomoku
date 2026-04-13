#!/bin/bash
# ============================================================
# Gomoku v2 Full Training + Packaging — MAX EFFORT CONFIG
#
# 仅在 run_smoke_on_mac.sh 通过后运行.
# Bootstrap + 迭代自对弈 + 打包 Gomoku_final.zip.
#
# 预计耗时: 11-14 小时 (一个通宵)
#
# Max effort 配置:
#   - 模型: 48 filters × 3 blocks (~650K params, vs 32f/2b 270K)
#   - Bootstrap: 200 局 × 400 sims × 80 epochs
#   - Iterate: 5 轮 × 80 局 × 400 sims × 20 epochs
#   - VCF depth 10, branch 8 (加深的战术搜索)
#   - Benchmark: 40 局每轮 (噪声 ±8%)
#   - 早停阈值 52% (小幅改进也视为进步)
#
# 流程:
#   Phase 1 (Bootstrap): pattern+VCF teacher 生成数据 -> π_0
#   Phase 2 (Iterate):   π_{i-1}+MCTS self-play -> π_i, 每轮 benchmark
#                         π_i vs π_{i-1}, 收敛则停止
#   Phase 3 (Package):   导出 ONNX + PyInstaller + .app
# ============================================================

set -e
cd "$(dirname "$0")"
PROJ_DIR="$(pwd)"

echo "============================================"
echo "  Gomoku v2 — Full Training + Packaging"
echo "  $(date)"
echo "============================================"
echo ""

# ---------- 1. 依赖 ----------
echo "[1/7] Installing dependencies..."
pip3 install --break-system-packages --quiet torch numpy onnxruntime pyinstaller 2>&1 | tail -3
echo "  Done."
echo ""

# ---------- 2. Bootstrap 训练 (Phase 1) ----------
echo "[2/7] Phase 1: Bootstrap training (pattern+VCF teacher -> π_0)..."
echo "  预计耗时: 90-150 分钟"
echo "  配置: 200 局 × 400 sims × 80 epochs, 48f/3b"
echo "  日志: ai_server/logs/bootstrap.log"
echo ""
cd "$PROJ_DIR/ai_server"
mkdir -p logs data/weights

nice -n 5 python3 -m nn.bootstrap \
    --games 200 \
    --simulations 400 \
    --workers 3 \
    --epochs 80 \
    --batch-size 128 \
    --lr 1e-3 \
    --filters 48 \
    --blocks 3 \
    --eval-games 20 \
    --random-eval-games 6 \
    --save-name gen_final.pt \
    --log-file bootstrap.log

echo "  Bootstrap done."
echo ""

# ---------- 3. Iterate (Phase 2) ----------
BOOTSTRAP_PT="$PROJ_DIR/ai_server/data/weights/gen_final.pt"
if [ ! -f "$BOOTSTRAP_PT" ]; then
    echo "ERROR: gen_final.pt not found!"
    exit 1
fi
echo "[3/7] Phase 2: Iterative self-play (policy improvement)..."
echo "  预计耗时: 8-10 小时 (5 iterations, early stop if no gain)"
echo "  配置: 5 × 80 局 × 400 sims × 20 epochs, 40-game benchmark"
echo "  日志: ai_server/logs/iterate.log"
echo ""

# 机器降温
echo "  Cool-down: 120s..."
sleep 120

nice -n 5 python3 -m nn.iterate \
    --initial-model "$BOOTSTRAP_PT" \
    --iterations 5 \
    --games-per-iter 80 \
    --simulations 400 \
    --epochs 20 \
    --batch-size 128 \
    --lr 2e-4 \
    --replay-size 20000 \
    --filters 48 \
    --blocks 3 \
    --vcf-depth 10 \
    --benchmark-games 40 \
    --benchmark-sims 150 \
    --converge-threshold 0.52 \
    --log-file iterate.log

echo "  Iterate done."
echo ""

# ---------- 4. 选最好的 checkpoint ----------
# 优先级: iter_3.pt > iter_2.pt > iter_1.pt > gen_final.pt
FINAL_PT=""
for candidate in iter_3.pt iter_2.pt iter_1.pt gen_final.pt; do
    if [ -f "$PROJ_DIR/ai_server/data/weights/$candidate" ]; then
        # iterate.log 最后一行有 "RECOMMENDED: iter_N.pt" 指示
        FINAL_PT="$PROJ_DIR/ai_server/data/weights/$candidate"
        break
    fi
done

# 也尝试从日志里读出推荐的 checkpoint
REC=$(grep -oE "RECOMMENDED: iter_[0-9]+\.pt" "$PROJ_DIR/ai_server/logs/iterate.log" 2>/dev/null | tail -1 | awk '{print $2}')
if [ -n "$REC" ] && [ -f "$PROJ_DIR/ai_server/data/weights/$REC" ]; then
    FINAL_PT="$PROJ_DIR/ai_server/data/weights/$REC"
fi

echo "[4/7] Final checkpoint: $FINAL_PT ($(du -h "$FINAL_PT" | cut -f1))"
echo ""

# 给机器降温一分钟
echo "  Cool-down: 60s..."
sleep 60

# ---------- 5. 导出 ONNX ----------
echo "[5/7] Exporting ONNX model from $FINAL_PT ..."
cd "$PROJ_DIR/ai_server"
python3 export_onnx.py "$FINAL_PT" -o data/weights/model.onnx --filters 48 --blocks 3 --input-channels 9 || {
    echo "  WARNING: ONNX export failed"
    echo "  Skipping ONNX — game will use MCTS fallback for Level 6"
}
echo ""

# ---------- 6. 打包 server ----------
echo "[6/7] Building standalone AI server..."
cd "$PROJ_DIR/ai_server"

ADD_MODEL_ARG=""
if [ -f "data/weights/model.onnx" ]; then
    ADD_MODEL_ARG="--add-data data/weights/model.onnx:."
fi

pyinstaller \
    --onefile \
    --name gomoku_ai_server \
    --add-data "protocol.py:." \
    $ADD_MODEL_ARG \
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

# ---------- 7. 组装 .app ----------
echo "[7/7] Packaging Gomoku.app..."
cd "$PROJ_DIR"

APP_ZIP="build/gobang_macos.zip"
if [ ! -f "$APP_ZIP" ]; then
    echo "ERROR: $APP_ZIP not found! Compile on Linux first."
    exit 1
fi

TMPDIR=$(mktemp -d)
unzip -q "$APP_ZIP" -d "$TMPDIR"

# 嵌入 AI server
cp "ai_server/dist/gomoku_ai_server" "$TMPDIR/Gomoku.app/Contents/MacOS/"
chmod +x "$TMPDIR/Gomoku.app/Contents/MacOS/gomoku_ai_server"

# 嵌入模型 (如果存在)
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
echo "  Training log: ai_server/logs/bootstrap.log"
echo ""
echo "  解压 $OUTPUT 双击 Gomoku.app 即可游玩"
echo "  Level 1-5: 内置 AI"
echo "  Level 6: 神经网络 AI (自动启动)"
echo "============================================"
