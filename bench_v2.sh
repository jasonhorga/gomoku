#!/bin/bash
# Benchmark free_v2_iter_3 against baseline + L4 minimax.
# Run on Mac after training completes.
#
# Usage from gomoku/ (the repo root):
#   bash bench_v2.sh
#
# Outputs: console summary + ai_server/logs/bench_v2.log

set -e
cd "$(dirname "$0")/ai_server"
mkdir -p logs

echo "=========================================="
echo " v2 Benchmark $(date)"
echo "=========================================="

python3 - <<'PY' 2>&1 | tee logs/bench_v2.log
import torch, time
import sys
sys.path.insert(0, '.')
from ai.game_logic import GameLogic, BLACK, WHITE, EMPTY
from nn.model import ModelWrapper
from ai.mcts_engine import MCTSEngine
from ai.minimax_engine import MinimaxEngine

def play(black, white, max_moves=150):
    g = GameLogic()
    while not g.game_over and len(g.move_history) < max_moves:
        e = black if g.current_player == BLACK else white
        r, c = e.choose_move(g)
        if not g.place_stone(r, c):
            break
    return g.winner, len(g.move_history)

def load(path):
    ckpt = torch.load(path, map_location='cpu', weights_only=False)
    nf = ckpt.get('num_filters', 128)
    nb = ckpt.get('num_res_blocks', 6)
    mw = ModelWrapper(num_filters=nf, num_res_blocks=nb, device='cpu')
    mw.model.load_state_dict(ckpt['state_dict'])
    mw.model.eval()
    return mw

def make_mcts(mw, sims=200):
    return MCTSEngine(simulations=sims, nn_model=mw,
                     use_pattern_prior=True, cnn_prior_weight=0.5,
                     vcf_depth=10, dirichlet_alpha=0.0)

mw_v2 = load('data/weights/free_v2_iter_3.pt')
mw_v1 = load('data/weights/best_model.pt')

# --- Bench 1: v2 vs baseline ---
print('\n=== free_v2_iter_3 vs best_model baseline (10 games, 200 sims) ===')
v2_wins = v1_wins = draws = 0
t0 = time.time()
for i in range(10):
    e_v2 = make_mcts(mw_v2)
    e_v1 = make_mcts(mw_v1)
    if i % 2 == 0:
        w, mv = play(e_v2, e_v1); v2_black = True
    else:
        w, mv = play(e_v1, e_v2); v2_black = False
    if (w == BLACK and v2_black) or (w == WHITE and not v2_black):
        v2_wins += 1; tag = 'v2'
    elif w == EMPTY:
        draws += 1; tag = 'D'
    else:
        v1_wins += 1; tag = 'baseline'
    print(f'  game {i+1:2d}: v2={"B" if v2_black else "W"} winner={tag} moves={mv}')
print(f'\nv2_iter_3 vs baseline: {v2_wins}/10 ({100*v2_wins/10:.0f}%)  baseline={v1_wins}  draws={draws}  ({time.time()-t0:.0f}s)')

# --- Bench 2: v2 vs L4 minimax ---
print('\n=== free_v2_iter_3 vs L4 minimax (10 games, 200 sims) ===')
cnn_wins = mm_wins = draws = 0
t0 = time.time()
for i in range(10):
    cnn = make_mcts(mw_v2)
    mm = MinimaxEngine(depth=4)
    if i % 2 == 0:
        w, mv = play(cnn, mm); cnn_black = True
    else:
        w, mv = play(mm, cnn); cnn_black = False
    if (w == BLACK and cnn_black) or (w == WHITE and not cnn_black):
        cnn_wins += 1; tag = 'CNN'
    elif w == EMPTY:
        draws += 1; tag = 'D'
    else:
        mm_wins += 1; tag = 'L4'
    print(f'  game {i+1:2d}: CNN={"B" if cnn_black else "W"} winner={tag} moves={mv}')
print(f'\nv2_iter_3 vs L4 minimax: {cnn_wins}/10 ({100*cnn_wins/10:.0f}%)  L4={mm_wins}  draws={draws}  ({time.time()-t0:.0f}s)')

# --- Bench 3: baseline vs L4 (control) ---
print('\n=== best_model vs L4 minimax (control, 10 games) ===')
b_wins = mm_wins = draws = 0
t0 = time.time()
for i in range(10):
    cnn = make_mcts(mw_v1)
    mm = MinimaxEngine(depth=4)
    if i % 2 == 0:
        w, mv = play(cnn, mm); cnn_black = True
    else:
        w, mv = play(mm, cnn); cnn_black = False
    if (w == BLACK and cnn_black) or (w == WHITE and not cnn_black):
        b_wins += 1; tag = 'CNN'
    elif w == EMPTY:
        draws += 1; tag = 'D'
    else:
        mm_wins += 1; tag = 'L4'
    print(f'  game {i+1:2d}: CNN={"B" if cnn_black else "W"} winner={tag} moves={mv}')
print(f'\nbaseline vs L4 minimax: {b_wins}/10 ({100*b_wins/10:.0f}%)  L4={mm_wins}  draws={draws}  ({time.time()-t0:.0f}s)')

# --- Summary ---
print('\n' + '='*50)
print(' SUMMARY')
print('='*50)
print(f' v2 vs baseline : {v2_wins}/10 ({100*v2_wins/10:.0f}%)  -- expected ≥ 60%')
print(f' v2 vs L4       : {cnn_wins}/10 ({100*cnn_wins/10:.0f}%) -- expected ≥ 70%')
print(f' baseline vs L4 : {b_wins}/10 ({100*b_wins/10:.0f}%) -- baseline reference')
print(f'\n DECISION:')
if v2_wins >= 6 and cnn_wins >= 7:
    print('   ✓ DEPLOY free_v2_iter_3 — clearly stronger than baseline')
elif cnn_wins > b_wins:
    print('   ⚠️  v2 better than baseline vs L4 but marginal — your call')
else:
    print('   ✗ v2 not clearly better — investigate or try iter_2')
PY

echo "=========================================="
echo " Done. Results in ai_server/logs/bench_v2.log"
echo "=========================================="
