# Gomoku AI Training Project

## Project Overview
Online + offline Gomoku (five-in-a-row) game. Godot 4 client + Swift plugin (CoreML) for runtime AI on iOS/macOS. Python (`ai_server/`) is **training only**, runs on Mac — no runtime Python server (deleted 2026-04-21 in P3 unification).
The AI uses AlphaZero-style training: pattern-guided MCTS teacher → CNN bootstrap → iterative self-play improvement.

## Architecture

### Godot side (scenes/, scripts/)
- Game UI, board rendering, online PvP (ENet), local PvP, AI integration, Chinese-only UI (Noto Sans CJK SC subset bundled)
- GDScript AI levels L1-L4 (random, heuristic, minimax, minimax+TT/iter-deepening/killer)
- L5 = pattern-MCTS via Swift plugin (1500 sims)
- L6 = CNN+MCTS via Swift plugin + CoreML (200 sims, 50/50 hybrid)
- Both iOS and macOS use the same Swift plugin (P3 unification 2026-04-21)

### Python training side (ai_server/) — training only, not part of runtime
```
ai_server/
  ai/
    game_logic.py      — 15x15 board, win detection, move generation, 9-channel tensor encoding
    pattern_eval.py    — Hand-crafted pattern scoring (open_four, open_three, split-three/four, etc.)
    mcts_engine.py     — MCTS with pattern priors + optional CNN priors
    minimax_engine.py  — Reference Python minimax (mirrors GDScript L4 for cross-checks)
    vcf_search.py      — Victory-by-Continuous-Four tactical search
    vct_search.py      — Victory-by-Continuous-Threat tactical search
  nn/
    model.py           — GomokuNet (ResNet, dual policy+value head, 9-ch input default)
    bootstrap.py       — Phase 1: train CNN to imitate pattern-MCTS teacher
    iterate.py         — Phase 2: iterative self-play improvement
    parallel_self_play.py — Multi-process self-play for bootstrap (current)
    self_play.py       — Single-process self-play (legacy, kept for debugging)
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
- Configurable: `--filters N --blocks B` (production: 128f/6b ≈ 2M params, bundled as best_model.pt)

## Training Pipeline

### Phase 1: Bootstrap (nn/bootstrap.py)
Pattern-MCTS teacher plays self-play games → CNN trained to imitate visit distributions.
```bash
python3 -m nn.bootstrap --games 200 --simulations 400 --epochs 50 \
    --filters 48 --blocks 3 --save-name gen_final.pt
```

### Phase 2: Iterate (nn/iterate.py)
CNN + MCTS self-play → train CNN on visit distributions → benchmark vs previous → repeat.
**Production recipe lives in `docs/retrain_plan.md` §A (§8.3 of `docs/ai_journey.md`)** — copy from there, don't hand-tune.

### Key CLI args for iterate.py
- `--cnn-prior-weight 0.5` — CNN vs pattern prior blend (0=all pattern, 1=all CNN). §9.1 sweep showed 0.5 optimal; do NOT raise without re-sweeping
- `--fresh-ratio 1.5` — Max fresh pool size as multiple of bootstrap pool (§8.3 / §9.2)
- `--checkpoint-prefix "free_v2_"` — Prefix for saved checkpoints
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

## Current Best Model (production)
- `best_model.pt` = `big_iter_1.pt` — 128f/6b, 66.9% vs bootstrap_128f6b, trained 2026-04-14/15
- `best_model.onnx` — ONNX export (used by export_coreml.py to produce .mlpackage)
- Bundled as `Resources/GomokuNet.mlmodelc` in signed iOS/macOS apps
- **Known limitation**: trained 2026-04-14, before split-three/split-four pattern detection was added 2026-04-16. The CNN doesn't recognize gap patterns. Retraining with the post-Apr 16 pattern_eval is the next major improvement (see docs/retrain_plan.md).
- Older checkpoints archived to `ai_server/data/weights/archive/`.

## Training on Mac

### Environment
- MacBook Air M5, 32GB RAM
- PyTorch with MPS backend (Apple Silicon GPU)
- Python 3.x, dependencies: torch, numpy

### Running training
Use the recipe in `docs/retrain_plan.md` §A (验证过的 §8.3 配方). Skeleton:
```bash
cd gomoku/ai_server
# Phase 1 — only re-run if pattern_eval.py changed semantically
python3 -m nn.bootstrap --games 200 --simulations 400 --epochs 50 \
    --filters 128 --blocks 6 --save-name bootstrap_128f6b.pt --log-file logs/bootstrap_128f6b.log

# Phase 2 — production retrain (§8.3 recipe)
python3 -m nn.iterate --initial-model data/weights/bootstrap_128f6b.pt \
    --iterations 5 --games-per-iter 150 --simulations 1600 \
    --epochs 5 --lr 3e-5 --replay-size 60000 --fresh-ratio 1.5 \
    --filters 128 --blocks 6 --vcf-depth 10 \
    --benchmark-games 40 --benchmark-sims 200 \
    --converge-threshold 0.50 --cnn-prior-weight 0.5 \
    --checkpoint-prefix "free_v2_" --log-file logs/free_v2_iterate.log
```
See `docs/retrain_plan.md` for parameter rationale (theory-strength table) and A.7 prior-weight sweep.

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
- Repo: github.com/jasonhorga/gomoku (**public** — was private originally, switched to public because GitHub Actions free-tier minutes are unlimited on public repos but capped on private; macOS notarization CI needed the unlimited tier)
- SSH key: ~/.ssh/id_ed25519_hejia
- Production branch: `main` (auto-merged from feature branches)
- **Push implication**: anything pushed to main is publicly visible + permanently archived (GitHub reflog + third-party mirrors + Copilot training scrape). gitignore covers `.p8` / `AuthKey_*` / `.env*`, but custom-named secrets could still leak. Diff-check for token-shaped strings before push.

## Working directory
**One repo, in Drive.** `/home/ubuntu/claude-web-data/hejia/gomoku/` is
a real git checkout that syncs to Mac via Google Drive. Run all git
operations directly here. Drive mount + git is fast in practice (~70ms
for status, ~30ms for log) once the FUSE cache warms; the earlier
"two directories" workaround (separate `hejia_local/gomoku_git/`) was
based on a worst-case assumption that didn't hold.

Drive sync covers source code, docs, and tracked weights/. Build
artifacts (`build/`, `.godot/`, `__pycache__/`) and runtime data
(`game_records/`, `archive/`) are gitignored — they stay local on
each machine and don't bloat Drive quota.
