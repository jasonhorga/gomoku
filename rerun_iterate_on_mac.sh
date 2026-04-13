#!/bin/bash
# Re-run iterate phase with hybrid MCTS fix (v3).
# Skips bootstrap — reuses gen_final.pt from previous run.
#
# Key fixes over v2/v3:
#   1. Continuous leaf eval: tanh(pattern_score_diff) gives MCTS gradient
#      (v3's discrete EMPTY→0.5 made search tree flat, visit dist ≈ priors)
#   2. Blended priors: 50% CNN policy + 50% pattern scores
#   3. Lower lr (1e-4) and fewer epochs (10) to avoid overfitting
#   4. Fresh pool capped at bootstrap size (50/50 split, bug-fixed)
#
# Estimated: 6-8 hours (5 iterations × ~75min/iter)

set -e
cd "$(dirname "$0")"
PROJ_DIR="$(pwd)"

echo "============================================"
echo "  Gomoku v2 — Iterate v4 (continuous leaf eval)"
echo "  $(date)"
echo "============================================"
echo "  Fix: continuous leaf eval (tanh of pattern score diff)"
echo "  Fix: blended priors, fresh pool cap, lower lr"
echo ""

BOOT_PT="$PROJ_DIR/ai_server/data/weights/gen_final.pt"
if [ ! -f "$BOOT_PT" ]; then
    echo "ERROR: gen_final.pt not found. Run full training first."
    exit 1
fi

# Back up old iter checkpoints so we don't overwrite silently
for f in iter_1.pt iter_2.pt iter_3.pt iter_4.pt iter_5.pt; do
    if [ -f "$PROJ_DIR/ai_server/data/weights/$f" ]; then
        mv "$PROJ_DIR/ai_server/data/weights/$f" "$PROJ_DIR/ai_server/data/weights/${f%.pt}_v2bad.pt"
    fi
done

cd "$PROJ_DIR/ai_server"
mkdir -p logs

echo "  Cool-down 30s before starting..."
sleep 30

echo "[Phase 2] Iterate (5 rounds, hybrid MCTS)..."
T0=$(date +%s)
nice -n 5 python3 -m nn.iterate \
    --initial-model "$BOOT_PT" \
    --iterations 5 \
    --games-per-iter 80 \
    --simulations 400 \
    --epochs 10 \
    --batch-size 128 \
    --lr 1e-4 \
    --replay-size 40000 \
    --filters 48 \
    --blocks 3 \
    --vcf-depth 10 \
    --benchmark-games 40 \
    --benchmark-sims 150 \
    --converge-threshold 0.52 \
    --log-file iterate_v4.log
ITER_TIME=$(($(date +%s) - T0))

echo ""
echo "============================================"
echo "  ITERATE RE-RUN DONE"
echo "============================================"
echo "  Total: ${ITER_TIME}s (~$((ITER_TIME / 60)) min)"
echo ""

# Find best checkpoint from log
REC=$(grep -oE "RECOMMENDED: iter_[0-9]+\.pt" logs/iterate_v4.log 2>/dev/null | tail -1 | awk '{print $2}')
if [ -z "$REC" ]; then
    REC="gen_final.pt"
fi

FINAL_PT="$PROJ_DIR/ai_server/data/weights/$REC"
if [ ! -f "$FINAL_PT" ]; then
    FINAL_PT="$BOOT_PT"
fi

echo "  Recommended checkpoint: $FINAL_PT"
echo ""
echo "  Next steps (manual):"
echo "    cd ai_server"
echo "    python3 export_onnx.py $FINAL_PT -o data/weights/model.onnx --filters 48 --blocks 3 --input-channels 9"
echo "    # then PyInstaller + .app assembly (from run_full_training_v2.sh steps 5-7)"
