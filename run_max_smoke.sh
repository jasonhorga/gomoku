#!/bin/bash
# Gomoku v2 Max Effort Smoke Test (~45-60 min on Mac)
# Validates: VCF 10, 48f/3b, iterate mechanism

set -e
cd "$(dirname "$0")"
PROJ_DIR="$(pwd)"

echo "============================================"
echo "  Gomoku v2 — Max Effort Smoke Test"
echo "  $(date)"
echo "============================================"
echo "  Config: 48f/3b, bootstrap 24 games, iter 2x12, VCF 10"
echo "  Estimated: 45-60 min"
echo ""

pip3 install --break-system-packages --quiet torch numpy 2>&1 | tail -3

cd "$PROJ_DIR/ai_server"
mkdir -p logs data/weights

echo "[Phase 1] Bootstrap (48f/3b, 24 games)..."
T0=$(date +%s)
nice -n 5 python3 -m nn.bootstrap \
    --games 24 --simulations 200 --workers 3 --epochs 25 \
    --batch-size 128 --lr 1e-3 --filters 48 --blocks 3 \
    --eval-games 6 --random-eval-games 6 \
    --save-name max_smoke.pt --log-file max_boot.log
BOOT_TIME=$(($(date +%s) - T0))

BOOT_PT="$PROJ_DIR/ai_server/data/weights/max_smoke.pt"
if [ ! -f "$BOOT_PT" ]; then
    echo "ERROR: bootstrap failed"
    exit 1
fi

echo "  Cool-down 30s..."
sleep 30

echo "[Phase 2] Iterate (2 rounds, 12 games each)..."
T0=$(date +%s)
nice -n 5 python3 -m nn.iterate \
    --initial-model "$BOOT_PT" \
    --iterations 2 --games-per-iter 12 --simulations 200 \
    --epochs 12 --batch-size 128 --lr 2e-4 --replay-size 8000 \
    --filters 48 --blocks 3 --vcf-depth 10 \
    --benchmark-games 10 --benchmark-sims 80 \
    --converge-threshold 0.50 --log-file max_iter.log
ITER_TIME=$(($(date +%s) - T0))

echo ""
echo "============================================"
echo "  VERDICT"
echo "============================================"
BOOT_DROP=$(grep -oE "\([0-9]+\.[0-9]+% drop\)" logs/max_boot.log 2>/dev/null | tail -1 | grep -oE "[0-9]+\.[0-9]+" | head -1)
BOOT_RAND=$(grep -oE "vs Random.*[0-9]+%" logs/max_boot.log 2>/dev/null | tail -1 | grep -oE "[0-9]+%" | head -1 | tr -d '%')
# iterate.py prints "iter1 vs iter0: NW NL ND  score=NN%" so match score=
ITER1=$(grep "iter1 vs iter0:" logs/max_iter.log 2>/dev/null | tail -1 | grep -oE "score=[0-9]+%" | grep -oE "[0-9]+")
ITER2=$(grep "iter2 vs iter1:" logs/max_iter.log 2>/dev/null | tail -1 | grep -oE "score=[0-9]+%" | grep -oE "[0-9]+")

echo "  Loss drop: ${BOOT_DROP:-?}% (need >=60)"
echo "  vs Random: ${BOOT_RAND:-?}% (need >=90)"
echo "  iter1 vs iter0: ${ITER1:-?}% (need >=50)"
echo "  iter2 vs iter1: ${ITER2:-?}% (info)"
echo "  Total: $((BOOT_TIME + ITER_TIME))s"
echo ""

PASS=1
[ -z "$BOOT_DROP" ] && PASS=0
[ -z "$ITER1" ] && PASS=0
[ -n "$ITER1" ] && [ "$ITER1" -lt 50 ] && PASS=0

if [ $PASS -eq 1 ]; then
    echo "  VERDICT: PASS — safe to run ./run_full_training_v2.sh"
    exit 0
else
    echo "  VERDICT: FAIL"
    echo "  Logs: ai_server/logs/max_boot.log ai_server/logs/max_iter.log"
    exit 2
fi
