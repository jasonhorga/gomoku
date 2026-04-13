#!/bin/bash
# ============================================================
# Gomoku v2 — Iteration Smoke Test (Mac)
#
# 在 run_smoke_on_mac.sh 通过后运行此脚本，验证
# Phase 2 的迭代自对弈循环能跑通。
#
# 预计耗时: ~10-15 分钟
# 通过条件: iter_1 vs iter_0 score >= 50% (说明没退化)
# ============================================================

set -e
cd "$(dirname "$0")"
PROJ_DIR="$(pwd)"

echo "============================================"
echo "  Gomoku v2 — Iterate Smoke Test"
echo "  $(date)"
echo "============================================"
echo ""

# ---------- 前置检查 ----------
BOOTSTRAP_PT="$PROJ_DIR/ai_server/data/weights/smoke_test.pt"
BOOTSTRAP_PKL="$PROJ_DIR/ai_server/data/weights/smoke_test_samples.pkl"

if [ ! -f "$BOOTSTRAP_PT" ]; then
    echo "ERROR: bootstrap checkpoint not found."
    echo "  Run ./run_smoke_on_mac.sh first."
    exit 1
fi

if [ ! -f "$BOOTSTRAP_PKL" ]; then
    echo "WARNING: bootstrap samples (.pkl) not found."
    echo "  Re-run ./run_smoke_on_mac.sh to create it."
    echo "  Without samples, iteration will overfit and fail."
    exit 1
fi

echo "[1/2] Found bootstrap checkpoint: $BOOTSTRAP_PT"
echo "      Samples: $BOOTSTRAP_PKL"
echo ""

# ---------- 跑 smoke test ----------
cd "$PROJ_DIR/ai_server"
mkdir -p logs data/weights

echo "[2/2] Running iterate smoke test..."
echo "  Config: 2 iterations × 4 games each"
echo "  Log: ai_server/logs/iterate_smoke.log"
echo ""

nice -n 5 python3 iterate_smoke_test.py 2>&1 | tee logs/iterate_smoke_console.log
RC=${PIPESTATUS[0]}

echo ""
echo "============================================"
echo "  ITERATE SMOKE VERDICT"
echo "============================================"

# 从日志里读迭代结果
SUMMARY=$(grep -E "iter[0-9]+ vs iter[0-9]+:" logs/iterate_smoke.log 2>/dev/null | tail -5)
if [ -n "$SUMMARY" ]; then
    echo "$SUMMARY"
    echo ""
fi

FIRST_SCORE=$(grep -oE "iter1 vs iter0: [0-9]+%" logs/iterate_smoke.log 2>/dev/null | tail -1 | grep -oE "[0-9]+")
if [ -n "$FIRST_SCORE" ] && [ "$FIRST_SCORE" -ge 50 ]; then
    echo "PASS — iter_1 did not regress (score=${FIRST_SCORE}%)"
    echo "You can now run ./run_full_training_v2.sh for the full pipeline."
    exit 0
else
    echo "FAIL — iter_1 regressed (score=${FIRST_SCORE:-unknown}%)"
    echo "Send the log to Claude:"
    echo "  cat ai_server/logs/iterate_smoke.log"
    exit 2
fi
