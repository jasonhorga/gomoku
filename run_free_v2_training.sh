#!/bin/bash
# Path A: Free v2 training to fix L6 vs L4 fork weakness.
#
# Recipe (per docs/retrain_plan.md decisions 2026-04-25):
#   - Architecture: 128f / 6b (no upgrade — see if data fix suffices)
#   - Data mix: 30% self-play + 50% pattern + 20% adversarial (L4 minimax)
#   - 6 iterations × 200 games × 800 sims (~15-18h on Mac M5)
#   - Initial model: current best_model.pt
#   - Lower lr (5e-5) since starting from a strong checkpoint
#   - Checkpoint prefix: free_v2_
#
# Usage from ai_server/:
#   nohup ./run_free_v2_training.sh > logs/free_v2_run.log 2>&1 &
#
# Then `tail -f logs/free_v2_run.log` to monitor.
# When done, run `pytest tests/test_fork_defense.py -v` to validate.

set -e

cd "$(dirname "$0")/ai_server"

# Sanity check: best_model.pt exists
if [ ! -f data/weights/best_model.pt ]; then
    echo "ERROR: data/weights/best_model.pt not found. Cannot start training."
    exit 1
fi

mkdir -p logs

echo "=========================================="
echo " Free v2 training starting at $(date)"
echo " Initial model: data/weights/best_model.pt"
echo " Output prefix: free_v2_iter_*.pt"
echo " Logs:    ai_server/logs/free_v2_iterate.log"
echo "=========================================="

python3 -m nn.iterate \
    --initial-model data/weights/best_model.pt \
    --iterations 6 \
    --games-per-iter 200 \
    --simulations 800 \
    --epochs 12 \
    --lr 5e-5 \
    --batch-size 128 \
    --replay-size 80000 \
    --filters 128 --blocks 6 \
    --vcf-depth 10 \
    --pattern-frac 0.5 \
    --adversarial-frac 0.2 \
    --benchmark-games 40 \
    --benchmark-sims 200 \
    --converge-threshold 0.45 \
    --cnn-prior-weight 0.5 \
    --fresh-ratio 1.0 \
    --checkpoint-prefix "free_v2_" \
    --log-file free_v2_iterate.log

echo "=========================================="
echo " Free v2 training finished at $(date)"
echo "=========================================="
echo ""
echo " Next steps:"
echo "   1. Run regression test:  cd ai_server && pytest tests/test_fork_defense.py -v"
echo "   2. Bench vs baseline:    python3 bench_l4_vs_l6.py (TODO write this)"
echo "   3. If pass → copy best iter → data/weights/best_model.pt"
echo "   4. Re-export ONNX/CoreML, re-build app, TestFlight"
