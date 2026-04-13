#!/bin/bash
# Verify that all my code changes synced from Linux to Mac
cd "$(dirname "$0")"

PASS=1
check() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if [ -n "$actual" ]; then
        echo "  OK   $label"
    else
        echo "  MISS $label (expected: $expected)"
        PASS=0
    fi
}

echo "============================================"
echo "  Gomoku v2 Sync Check"
echo "============================================"
echo ""

echo "[New files]"
if [ -f ai_server/ai/vcf_search.py ]; then
    echo "  OK   ai_server/ai/vcf_search.py"
else
    echo "  MISS ai_server/ai/vcf_search.py (critical)"
    PASS=0
fi
if [ -f ai_server/nn/iterate.py ]; then
    echo "  OK   ai_server/nn/iterate.py"
else
    echo "  MISS ai_server/nn/iterate.py (critical)"
    PASS=0
fi
if [ -f ai_server/diag_selfplay.py ]; then
    echo "  OK   ai_server/diag_selfplay.py"
else
    echo "  MISS ai_server/diag_selfplay.py"
fi
echo ""

echo "[pattern_eval.py]"
check "DEFENSE_WEIGHT = 0.8" "0.8" \
    "$(grep '^DEFENSE_WEIGHT = 0.8' ai_server/ai/pattern_eval.py 2>/dev/null)"
check "DOUBLE_THREAT_BONUS = 3.0" "3.0" \
    "$(grep 'DOUBLE_THREAT_BONUS = 3.0' ai_server/ai/pattern_eval.py 2>/dev/null)"
check "STRONG_PATTERN_THRESHOLD" "900" \
    "$(grep 'STRONG_PATTERN_THRESHOLD' ai_server/ai/pattern_eval.py 2>/dev/null)"
echo ""

echo "[mcts_engine.py]"
check "vcf_depth=10 default" "vcf_depth=10" \
    "$(grep 'vcf_depth=10, vcf_branch=8' ai_server/ai/mcts_engine.py 2>/dev/null)"
check "find_vcf import" "from ai.vcf_search" \
    "$(grep 'from ai.vcf_search import find_vcf' ai_server/ai/mcts_engine.py 2>/dev/null)"
check "max-normalized prior (no log1p)" "no log1p line" \
    "$(grep -L 'arr = np.log1p' ai_server/ai/mcts_engine.py 2>/dev/null)"
echo ""

echo "[vcf_search.py]"
if [ -f ai_server/ai/vcf_search.py ]; then
    check "counter-check bug fixed" "O(candidates) note" \
        "$(grep 'unusably slow' ai_server/ai/vcf_search.py 2>/dev/null)"
    check "depth=10 default" "max_depth=10" \
        "$(grep 'max_depth=10' ai_server/ai/vcf_search.py 2>/dev/null)"
fi
echo ""

echo "[bootstrap.py]"
check "saves samples.pkl" "Saved training samples" \
    "$(grep 'Saved training samples' ai_server/nn/bootstrap.py 2>/dev/null)"
check "game recording" "Recorded.*sample games" \
    "$(grep 'Recorded.*sample games' ai_server/nn/bootstrap.py 2>/dev/null)"
echo ""

echo "[parallel_self_play.py]"
check "_random_opening function" "def _random_opening" \
    "$(grep 'def _random_opening' ai_server/nn/parallel_self_play.py 2>/dev/null)"
check "record_moves param" "record_moves" \
    "$(grep 'record_moves' ai_server/nn/parallel_self_play.py 2>/dev/null | head -1)"
echo ""

echo "[iterate.py]"
if [ -f ai_server/nn/iterate.py ]; then
    check "preloads bootstrap samples" "Pre-filled replay" \
        "$(grep 'Pre-filled replay buffer' ai_server/nn/iterate.py 2>/dev/null)"
    check "play_match function" "def play_match" \
        "$(grep 'def play_match' ai_server/nn/iterate.py 2>/dev/null)"
    check "convergence check" "converge_threshold" \
        "$(grep 'converge_threshold' ai_server/nn/iterate.py 2>/dev/null | head -1)"
fi
echo ""

echo "[model.py]"
check "auto-detect shape on load" "ckpt_nf" \
    "$(grep 'ckpt_nf' ai_server/nn/model.py 2>/dev/null | head -1)"
echo ""

echo "[run_full_training_v2.sh]"
check "uses 48f/3b" "filters 48" \
    "$(grep '\-\-filters 48' run_full_training_v2.sh 2>/dev/null | head -1)"
check "calls iterate phase" "nn.iterate" \
    "$(grep 'nn.iterate' run_full_training_v2.sh 2>/dev/null)"
check "5 iterations" "iterations 5" \
    "$(grep '\-\-iterations 5' run_full_training_v2.sh 2>/dev/null)"
echo ""

echo "============================================"
if [ $PASS -eq 1 ]; then
    echo "  RESULT: ALL SYNCED OK"
    echo "  Safe to run ./run_max_smoke.sh"
else
    echo "  RESULT: SOME FILES NOT SYNCED"
    echo "  Above 'MISS' lines need re-sync or manual fix"
fi
echo "============================================"
