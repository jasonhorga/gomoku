#!/bin/bash
# Verify: does external benchmark reproduce iterate.py's internal result?
#
# iterate log said: iter_1 vs iter_0 = 66% (23W-10L-7D, 40 games)
# If this script produces ~60-70%, the benchmark machinery is correct
# and big_iter_1.pt is genuinely the best checkpoint.
# If it's much lower, there's a bug.
#
# Uses 80 games instead of 40 to cut variance.
set -e
cd "$(dirname "$0")/ai_server"

echo "============================================"
echo "  Verify: big_iter_1 vs bootstrap_128f6b"
echo "  Expect ~66% if log's internal benchmark is reproducible"
echo "============================================"
mkdir -p logs
python3 -u benchmark_models.py \
    --model-a data/weights/big_iter_1.pt \
    --model-b data/weights/bootstrap_128f6b.pt \
    --games 80 --sims 200 \
    --filters 128 --blocks 6 \
    --vcf-depth 10 --cnn-prior-weight 0.5 2>&1 | tee logs/verify_iter1.log
