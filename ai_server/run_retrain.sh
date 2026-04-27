#!/bin/bash
# Path A retrain on Mac — §8.3 recipe from docs/retrain_plan.md §A.4
# Usage: bash ai_server/run_retrain.sh

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

LOG_DIR="logs"
PID_FILE="$LOG_DIR/free_v2.pid"
TRAIN_LOG="$LOG_DIR/free_v2_iterate.log"
CONSOLE_LOG="$LOG_DIR/free_v2_console.log"

mkdir -p "$LOG_DIR"

# --- Already running? ---
if [ -f "$PID_FILE" ] && kill -0 "$(cat $PID_FILE)" 2>/dev/null; then
    echo "Training already running (PID $(cat $PID_FILE))"
    echo "  Watch: tail -f $SCRIPT_DIR/$TRAIN_LOG"
    echo "  Stop:  kill \$(cat $SCRIPT_DIR/$PID_FILE)"
    exit 1
fi

# --- Pre-flight ---
echo "=== Pre-flight ==="
[ -f "data/weights/bootstrap_128f6b.pt" ] || { echo "MISSING: bootstrap_128f6b.pt"; exit 1; }
[ -f "data/weights/bootstrap_128f6b_samples.pkl" ] || { echo "MISSING: bootstrap_128f6b_samples.pkl"; exit 1; }
python3 -c "import torch; assert torch.backends.mps.is_available()" 2>/dev/null \
    || { echo "MPS unavailable — install PyTorch with MPS support"; exit 1; }
echo "OK: bootstrap files + MPS"
echo ""
echo "Repo at:"
git log -1 --oneline
echo ""

# --- Launch ---
echo "=== Starting overnight retrain (~14-16h) ==="
nohup caffeinate -is python3 -m nn.iterate \
    --initial-model data/weights/bootstrap_128f6b.pt \
    --iterations 5 \
    --games-per-iter 150 \
    --simulations 1600 \
    --epochs 5 \
    --lr 3e-5 \
    --replay-size 60000 \
    --fresh-ratio 1.5 \
    --filters 128 --blocks 6 \
    --vcf-depth 10 \
    --benchmark-games 40 \
    --benchmark-sims 200 \
    --converge-threshold 0.50 \
    --cnn-prior-weight 0.5 \
    --checkpoint-prefix "free_v2_" \
    --log-file "$TRAIN_LOG" \
    > "$CONSOLE_LOG" 2>&1 &

PID=$!
echo "$PID" > "$PID_FILE"

# --- Confirm alive after 5s ---
sleep 5
if ! kill -0 "$PID" 2>/dev/null; then
    echo "ERROR: process died immediately."
    echo "--- console log ---"
    cat "$CONSOLE_LOG"
    rm -f "$PID_FILE"
    exit 1
fi

echo ""
echo "Started. PID: $PID"
echo ""
echo "--- First lines of console output ---"
head -20 "$CONSOLE_LOG" 2>/dev/null || echo "(no output yet, that's normal)"
echo ""
echo "=== Useful commands ==="
echo "  Watch:   tail -f $SCRIPT_DIR/$TRAIN_LOG"
echo "  Status:  ps -p $PID"
echo "  Stop:    kill $PID"
echo ""
echo "Mac can be locked but DON'T close the lid (clamshell forces sleep)."
echo "When done (~tomorrow): models at data/weights/free_v2_iter_*.pt"
