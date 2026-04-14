#!/bin/bash
# Benchmark big_iter_3 (128f/6b after 3 iterations) vs bootstrap_128f6b.
# Score > 55% means iterate training actually improved the model.
set -e
cd "$(dirname "$0")/ai_server"

python3 benchmark_models.py \
    --model-a data/weights/big_iter_3.pt \
    --model-b data/weights/bootstrap_128f6b.pt \
    --games 40 --sims 200 \
    --filters 128 --blocks 6 \
    --vcf-depth 10 \
    --cnn-prior-weight 0.5
