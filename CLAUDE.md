# Gomoku AI Training Project

## Project Overview
Online + offline Gomoku (five-in-a-row) game built with Godot 4 + Python AI backend.
The AI uses AlphaZero-style training: pattern-guided MCTS teacher → CNN bootstrap → iterative self-play improvement.

## Architecture

### Godot side (scenes/, scripts/)
- Game UI, board rendering, online PvP (ENet), local PvP, AI integration
- GDScript AI levels 1-5 (random, heuristic, minimax, MCTS)
- Level 6 = Python CNN via TCP

### Python AI side (ai_server/)
```
ai_server/
  ai/
    game_logic.py      — 15x15 board, win detection, move generation
    pattern_eval.py    — Hand-crafted pattern scoring (open_four, open_three, etc.)
    mcts_engine.py     — MCTS with pattern priors + optional CNN priors
    vcf_search.py      — Victory-by-Continuous-Four tactical search
  nn/
    model.py           — GomokuNet (ResNet, dual policy+value head)
    bootstrap.py       — Phase 1: train CNN to imitate pattern-MCTS teacher
    iterate.py         — Phase 2: iterative self-play improvement
    parallel_self_play.py — Multi-process self-play for bootstrap
    trainer.py         — Training loop (Adam, policy CE + value MSE)
    augment.py         — 8x augmentation (rotations + flips)
  data/weights/        — Model checkpoints (.pt files)
  logs/                — Training logs
```

### CNN Architecture (model.py)
- Input: 9 channels × 15 × 15 (2 stone planes + 6 pattern features + last move)
- Body: initial conv → N residual blocks (each = 2 × conv+BN+ReLU)
- Policy head: conv → FC → 225 softmax (move probabilities)
- Value head: conv → FC → FC → 1 tanh (position evaluation -1 to +1)
- Configurable: `--filters N --blocks B` (current: 48f/3b = 361k params)

## Training Pipeline

### Phase 1: Bootstrap (nn/bootstrap.py)
Pattern-MCTS teacher plays self-play games → CNN trained to imitate visit distributions.
```bash
python3 -m nn.bootstrap --games 200 --simulations 400 --epochs 50 \
    --filters 48 --blocks 3 --save-name gen_final.pt
```

### Phase 2: Iterate (nn/iterate.py)  
CNN + MCTS self-play → train CNN on visit distributions → benchmark vs previous → repeat.
```bash
python3 -m nn.iterate --initial-model data/weights/gen_final.pt \
    --iterations 8 --games-per-iter 150 --simulations 800 \
    --epochs 10 --lr 1e-4 --filters 48 --blocks 3
```

### Key CLI args for iterate.py
- `--cnn-prior-weight 0.5` — CNN vs pattern prior blend (0=all pattern, 1=all CNN)
- `--fresh-ratio 1.0` — Max fresh pool size as multiple of bootstrap pool
- `--checkpoint-prefix "phA_"` — Prefix for saved checkpoints
- `--converge-threshold 0.50` — Stop when score drops below this

## Hybrid MCTS Design (CRITICAL)

The MCTS engine has 3 modes depending on configuration:

1. **Pattern-only** (nn_model=None): priors from pattern_eval, leaf eval from pattern scores
2. **Hybrid** (nn_model + use_pattern_prior=True): blended priors (CNN × cnn_prior_weight + pattern × rest), leaf eval = continuous pattern score (tanh)
3. **Pure CNN** (nn_model + use_pattern_prior=False): CNN priors, CNN value head for leaf eval

**Self-play and benchmarks use Hybrid mode.** This is critical because:
- The CNN value head is too noisy for a small network → using it for leaf eval makes MCTS weaker
- Pattern-based continuous leaf eval (`_continuous_leaf_value`) uses `tanh(score_diff / 1000)` to give MCTS gradient signal
- The old discrete `_static_leaf_value` returned EMPTY for most positions → flat 0.5 signal → MCTS couldn't differentiate moves

## Known Issues & Lessons Learned

### CNN prior weight MUST stay ≤ 50%
- Tested 75% and 90% CNN prior weight → catastrophic regression (12% score)
- The small CNN's priors are not reliable enough to lead search
- 50/50 blend with pattern priors is the safe configuration
- This may improve with a larger network

### Fresh pool cap when bootstrap is empty
- When no bootstrap samples are loaded, `int(0 * fresh_ratio) = 0`
- Python's `list[-0:]` returns the full list, so cap doesn't activate
- Fresh pool grows unbounded (174k+ samples by iter4)
- Not catastrophic (Phase A still got 3 good iterations) but should be fixed:
  ```python
  if len(bootstrap_pool) == 0:
      fresh_cap = args.replay_size
  ```

### Bootstrap samples not needed for strong models
- iterate.py looks for `{model_path}_samples.pkl` for bootstrap anchor pool
- Starting from a strong checkpoint (iter_3+), bootstrap data is lower quality than self-play
- Warning "will overfit on fresh games only" is misleading — it's actually fine

### Replay buffer history
- v1: Single FIFO buffer, one iteration's data evicted ALL bootstrap → 40% regression
- v2: Two-pool (bootstrap anchor + fresh FIFO) → fixed forgetting
- Current: Bootstrap pool not needed for strong models, fresh pool with replay_size cap

## Current Best Models
- `gen_final.pt` — Bootstrap model (pattern-MCTS teacher, 48f/3b)
- `iter_3.pt` — 3 iterations from gen_final (v4, continuous leaf eval, 48f/3b)
- `phA_iter_3.pt` — 3 more iterations from iter_3 (800 sims, 150 games/iter, 48f/3b)

## Training on Mac

### Environment
- MacBook Air M5, 32GB RAM
- PyTorch with MPS backend (Apple Silicon GPU)
- Python 3.x, dependencies: torch, numpy

### Running training
```bash
cd gomoku/ai_server
python3 -m nn.bootstrap --games 200 --simulations 400 --epochs 50 \
    --filters 128 --blocks 6 --save-name bootstrap_128f6b.pt --log-file bootstrap_128f6b.log

python3 -m nn.iterate --initial-model data/weights/bootstrap_128f6b.pt \
    --iterations 15 --games-per-iter 150 --simulations 800 \
    --epochs 10 --lr 1e-4 --replay-size 60000 \
    --filters 128 --blocks 6 --vcf-depth 10 \
    --benchmark-games 40 --benchmark-sims 200 \
    --converge-threshold 0.50 \
    --cnn-prior-weight 0.5 \
    --log-file iterate_128f6b.log
```

### Monitoring training
- Check log files in `ai_server/logs/`
- Key patterns to grep: `vs iter`, `score=`, `self-play done`, `loss`, `Convergence`
- Healthy signs: score > 52% each iteration, loss decreasing, games resolving (not all draws)
- Bad signs: score < 50% (regression), all games drawing at max moves, loss not decreasing

### If training fails
1. Check the log for the failure pattern
2. If score < 50% on iter1: training data quality issue, check self-play game stats
3. If too many draws: leaf evaluation might be flat, check _continuous_leaf_value
4. If loss not decreasing: lr too low or data issue
5. Fix the code and restart from the last good checkpoint

## GitHub
- Repo: github.com/jasonhorga/gomoku (private)
- Git operations done from local disk copy due to Drive mount slowness
- SSH key: ~/.ssh/id_ed25519_hejia
