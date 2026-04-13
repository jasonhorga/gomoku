#!/bin/bash
# ============================================================
# Gomoku v2 Smoke Test
#
# 10-20 分钟快速验证新训练策略是否真的能让 CNN 学到东西.
# 跑完立即看结果, 如果 PASS 就跑 run_full_training_v2.sh.
# 如果 FAIL 就不要烧一晚机器 --- 回来找 Claude.
#
# 用法:
#   cd gobang
#   chmod +x run_smoke_on_mac.sh
#   ./run_smoke_on_mac.sh
#
# 关键指标 (日志最后的 VERDICT 区块):
#   loss       : 初始 -> 终值 (期望至少 15% 下降)
#   vs Random  : 期望 >= 90%
#   vs Teacher : 期望 >= 20% (有学习信号)
# ============================================================

set -e
cd "$(dirname "$0")"
PROJ_DIR="$(pwd)"

echo "============================================"
echo "  Gomoku v2 — Smoke Test"
echo "  $(date)"
echo "============================================"
echo ""

# ---------- 依赖 ----------
echo "[1/2] Installing dependencies (torch/numpy)..."
pip3 install --break-system-packages --quiet torch numpy 2>&1 | tail -3
echo "  Done."
echo ""

# ---------- 烟雾测试 ----------
echo "[2/2] Running smoke test..."
echo "  预计耗时: 10-20 分钟"
echo "  日志: ai_server/logs/smoke_test.log"
echo ""
cd "$PROJ_DIR/ai_server"
mkdir -p logs data/weights

# 用 nice 降低优先级, 减少热降频
nice -n 5 python3 smoke_test.py

EXIT_CODE=$?
echo ""
echo "============================================"
if [ $EXIT_CODE -eq 0 ]; then
    echo "  SMOKE TEST: PASS ✓"
    echo "============================================"
    echo ""
    echo "  训练策略验证成功. 可以运行完整训练:"
    echo "    ./run_full_training_v2.sh"
    echo ""
elif [ $EXIT_CODE -eq 2 ]; then
    echo "  SMOKE TEST: FAIL ✗"
    echo "============================================"
    echo ""
    echo "  训练指标没达到阈值. 看日志:"
    echo "    ai_server/logs/smoke_test.log"
    echo ""
    echo "  把 VERDICT 区块发给 Claude, 不要直接跑完整训练"
    echo ""
else
    echo "  SMOKE TEST: CRASHED (exit $EXIT_CODE)"
    echo "============================================"
    echo ""
    echo "  看日志里的 traceback: ai_server/logs/smoke_test.log"
    echo ""
fi

exit $EXIT_CODE
