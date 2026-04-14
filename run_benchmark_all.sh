#!/bin/bash
# Diagnose which model is the true best.
# Runs 3 benchmarks sequentially:
#   1. big_iter_1 vs bootstrap   — did iter_1 already regress or only iter_3?
#   2. big_iter_2 vs bootstrap   — intermediate check
#   3. bootstrap_128f6b vs phA_iter_3 (small)  — does big bootstrap beat small iter_3?
set -e
cd "$(dirname "$0")/ai_server"

echo "============================================"
echo "  [1/3] big_iter_1 vs bootstrap_128f6b"
echo "============================================"
python3 benchmark_models.py \
    --model-a data/weights/big_iter_1.pt \
    --model-b data/weights/bootstrap_128f6b.pt \
    --games 40 --sims 200 --filters 128 --blocks 6 \
    --vcf-depth 10 --cnn-prior-weight 0.5

echo ""
echo "============================================"
echo "  [2/3] big_iter_2 vs bootstrap_128f6b"
echo "============================================"
python3 benchmark_models.py \
    --model-a data/weights/big_iter_2.pt \
    --model-b data/weights/bootstrap_128f6b.pt \
    --games 40 --sims 200 --filters 128 --blocks 6 \
    --vcf-depth 10 --cnn-prior-weight 0.5

echo ""
echo "============================================"
echo "  DONE.  Post all 3 scores to decide final model."
echo "============================================"
