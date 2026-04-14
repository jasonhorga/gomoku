#!/bin/bash
# Overnight training with 128f/6b network (2M params).
#
# The 128f/6b bootstrap already has loss=1.05 (much better than 48f/3b's 1.57).
# This means the CNN closely imitates the teacher, so iterate needs:
#   - More sims (1600) to search DEEPER than the 400-sim teacher
#   - Fewer epochs (5) to avoid overfitting the bigger network
#   - Lower lr (3e-5) for conservative fine-tuning
#   - CNN prior weight 0.5 (proven safe, >0.5 causes regression)
#
# Estimated: 6-8 hours on Mac M5.

set -e
cd "$(dirname "$0")"
PROJ_DIR="$(pwd)"
cd "$PROJ_DIR/ai_server"
mkdir -p logs data/weights

# Use existing 128f/6b bootstrap if available, otherwise bootstrap first
BOOT_PT="$PROJ_DIR/ai_server/data/weights/bootstrap_128f6b.pt"

if [ ! -f "$BOOT_PT" ]; then
    echo "============================================"
    echo "  Phase 0: Bootstrap 128f/6b"
    echo "  $(date)"
    echo "============================================"
    nice -n 5 python3 -m nn.bootstrap \
        --games 200 --simulations 400 --workers 3 --epochs 50 \
        --batch-size 128 --lr 1e-3 --filters 128 --blocks 6 \
        --eval-games 10 --random-eval-games 6 \
        --save-name bootstrap_128f6b.pt --log-file bootstrap_128f6b.log
    BOOT_PT="$PROJ_DIR/ai_server/data/weights/bootstrap_128f6b.pt"
fi

echo ""
echo "============================================"
echo "  128f/6b Overnight Iterate"
echo "  $(date)"
echo "============================================"
echo "  Model: $BOOT_PT"
echo "  Key: 1600 sims, 5 epochs, lr=3e-5"
echo ""

T_ALL=$(date +%s)

nice -n 5 python3 -m nn.iterate \
    --initial-model "$BOOT_PT" \
    --iterations 20 \
    --games-per-iter 150 \
    --simulations 1600 \
    --epochs 5 \
    --batch-size 128 \
    --lr 3e-5 \
    --replay-size 60000 \
    --filters 128 \
    --blocks 6 \
    --vcf-depth 10 \
    --benchmark-games 40 \
    --benchmark-sims 200 \
    --converge-threshold 0.50 \
    --cnn-prior-weight 0.5 \
    --fresh-ratio 1.5 \
    --checkpoint-prefix "big_" \
    --log-file overnight_128f6b.log

T_TOTAL=$(($(date +%s) - T_ALL))

echo ""
echo "============================================"
echo "  DONE"
echo "  $(date)"
echo "============================================"
echo "  Total: ${T_TOTAL}s (~$((T_TOTAL / 3600))h $((T_TOTAL % 3600 / 60))m)"

# Find best checkpoint
REC=$(grep -oE "RECOMMENDED: big_iter_[0-9]+\.pt" logs/overnight_128f6b.log 2>/dev/null | tail -1 | sed 's/RECOMMENDED: //')
if [ -z "$REC" ]; then
    REC="bootstrap_128f6b.pt"
fi
echo "  Best model: $REC"
echo ""
echo "  Export:"
echo "    python3 export_onnx.py data/weights/$REC -o data/weights/model.onnx --filters 128 --blocks 6 --input-channels 9"
