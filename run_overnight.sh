#!/bin/bash
# Gomoku overnight training — 3-phase iterate with escalating CNN influence.
#
# Phase A (warmup):  50% CNN priors, 800 sims  — reach pattern-eval ceiling
# Phase B (break):   75% CNN priors, 800 sims  — CNN starts leading search
# Phase C (push):    90% CNN priors, 1200 sims — deep search, CNN dominant
#
# Each phase chains from the previous best checkpoint.
# Total estimated: 6-8 hours on Mac M5.

set -e
cd "$(dirname "$0")"
PROJ_DIR="$(pwd)"
cd "$PROJ_DIR/ai_server"
mkdir -p logs data/weights

BOOT_PT="$PROJ_DIR/ai_server/data/weights/gen_final.pt"
# Use iter_3.pt from v4 run as starting point (already stronger than bootstrap)
START_PT="$PROJ_DIR/ai_server/data/weights/iter_3.pt"
if [ ! -f "$START_PT" ]; then
    START_PT="$BOOT_PT"
fi
if [ ! -f "$START_PT" ]; then
    echo "ERROR: no starting checkpoint found"
    exit 1
fi

echo "============================================"
echo "  Gomoku — Overnight Training"
echo "  $(date)"
echo "============================================"
echo "  Starting from: $START_PT"
echo "  3 phases, ~6-8 hours total"
echo ""

T_ALL=$(date +%s)

# ============================================================
# Phase A: Warmup — 50% CNN priors, 800 sims
# Establish strong base above pattern-eval level
# ============================================================
echo ""
echo "==============================="
echo "  Phase A: Warmup (50% CNN)"
echo "  $(date)"
echo "==============================="

nice -n 5 python3 -m nn.iterate \
    --initial-model "$START_PT" \
    --iterations 8 \
    --games-per-iter 150 \
    --simulations 800 \
    --epochs 10 \
    --batch-size 128 \
    --lr 1e-4 \
    --replay-size 60000 \
    --filters 48 \
    --blocks 3 \
    --vcf-depth 10 \
    --benchmark-games 40 \
    --benchmark-sims 200 \
    --converge-threshold 0.50 \
    --cnn-prior-weight 0.5 \
    --fresh-ratio 1.5 \
    --checkpoint-prefix "phA_" \
    --log-file overnight_phA.log

# Find Phase A's best checkpoint
BEST_A=$(grep -oE "RECOMMENDED: phA_iter_[0-9]+\.pt" logs/overnight_phA.log 2>/dev/null | tail -1 | sed 's/RECOMMENDED: //')
if [ -z "$BEST_A" ]; then
    BEST_A="phA_iter_1.pt"
fi
BEST_A_PT="$PROJ_DIR/ai_server/data/weights/$BEST_A"
if [ ! -f "$BEST_A_PT" ]; then
    BEST_A_PT="$START_PT"
fi
echo "  Phase A best: $BEST_A_PT"

# ============================================================
# Phase B: Breakthrough — 75% CNN priors, 800 sims
# CNN leads exploration, pattern provides safety
# ============================================================
echo ""
echo "==============================="
echo "  Phase B: Breakthrough (75% CNN)"
echo "  $(date)"
echo "==============================="

nice -n 5 python3 -m nn.iterate \
    --initial-model "$BEST_A_PT" \
    --iterations 8 \
    --games-per-iter 150 \
    --simulations 800 \
    --epochs 10 \
    --batch-size 128 \
    --lr 8e-5 \
    --replay-size 60000 \
    --filters 48 \
    --blocks 3 \
    --vcf-depth 10 \
    --benchmark-games 40 \
    --benchmark-sims 200 \
    --converge-threshold 0.50 \
    --cnn-prior-weight 0.75 \
    --fresh-ratio 2.0 \
    --checkpoint-prefix "phB_" \
    --log-file overnight_phB.log

BEST_B=$(grep -oE "RECOMMENDED: phB_iter_[0-9]+\.pt" logs/overnight_phB.log 2>/dev/null | tail -1 | sed 's/RECOMMENDED: //')
if [ -z "$BEST_B" ]; then
    BEST_B="phB_iter_1.pt"
fi
BEST_B_PT="$PROJ_DIR/ai_server/data/weights/$BEST_B"
if [ ! -f "$BEST_B_PT" ]; then
    BEST_B_PT="$BEST_A_PT"
fi
echo "  Phase B best: $BEST_B_PT"

# ============================================================
# Phase C: Push — 90% CNN priors, 1200 sims
# Deep search, CNN dominant, break new ground
# ============================================================
echo ""
echo "==============================="
echo "  Phase C: Push (90% CNN, 1200 sims)"
echo "  $(date)"
echo "==============================="

nice -n 5 python3 -m nn.iterate \
    --initial-model "$BEST_B_PT" \
    --iterations 8 \
    --games-per-iter 150 \
    --simulations 1200 \
    --epochs 10 \
    --batch-size 128 \
    --lr 5e-5 \
    --replay-size 60000 \
    --filters 48 \
    --blocks 3 \
    --vcf-depth 10 \
    --benchmark-games 40 \
    --benchmark-sims 200 \
    --converge-threshold 0.50 \
    --cnn-prior-weight 0.9 \
    --fresh-ratio 3.0 \
    --checkpoint-prefix "phC_" \
    --log-file overnight_phC.log

BEST_C=$(grep -oE "RECOMMENDED: phC_iter_[0-9]+\.pt" logs/overnight_phC.log 2>/dev/null | tail -1 | sed 's/RECOMMENDED: //')
if [ -z "$BEST_C" ]; then
    BEST_C="phC_iter_1.pt"
fi
BEST_C_PT="$PROJ_DIR/ai_server/data/weights/$BEST_C"
if [ ! -f "$BEST_C_PT" ]; then
    BEST_C_PT="$BEST_B_PT"
fi

T_TOTAL=$(($(date +%s) - T_ALL))

echo ""
echo "============================================"
echo "  OVERNIGHT TRAINING COMPLETE"
echo "  $(date)"
echo "============================================"
echo "  Total time: ${T_TOTAL}s (~$((T_TOTAL / 3600))h $((T_TOTAL % 3600 / 60))m)"
echo ""
echo "  Phase A best: $BEST_A"
echo "  Phase B best: $BEST_B"
echo "  Phase C best: $BEST_C"
echo ""
echo "  Final model: $BEST_C_PT"
echo ""
echo "  Next steps:"
echo "    cd ai_server"
echo "    python3 export_onnx.py $BEST_C_PT -o data/weights/model.onnx --filters 48 --blocks 3 --input-channels 9"
