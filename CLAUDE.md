# Gomoku AI Training Project

Online + offline 五子棋 game. **Runtime AI** = Godot 4 client + Swift plugin + CoreML on iOS/macOS (no Python at runtime; server deleted 2026-04-21 in P3 unification). **Python `ai_server/`** runs on Mac for training only.

## Critical operational rules (don't break these)

1. **Don't train/benchmark on EC2.** Shared infra. Run on user's Mac (M5).
2. **Public repo.** Always token-scan `git diff` before push (see memory `feedback_default_push.md`).
3. **Hybrid MCTS uses Pattern leaf eval, NOT CNN value head.** Don't "fix" this — using value head makes MCTS weaker because the small CNN's value is too noisy. (`docs/ai_journey.md` §5.6, §10)
4. **CNN prior weight ≤ 50%.** Tested 75/90% → catastrophic 12% score regression. The small CNN's priors aren't reliable enough to lead search. (`docs/ai_journey.md` §9.1)
5. **Don't hand-tune retrain hyperparams.** Use `docs/retrain_plan.md` §A verbatim — it has a theory-strength table justifying every parameter.

## Production state

- Best model: `ai_server/data/weights/best_model.pt` (= `big_iter_1.pt`, 128f/6b, 66.9% vs bootstrap, trained 2026-04-14)
- Bundled as `Resources/GomokuNet.mlmodelc` in signed iOS/macOS apps (via `best_model.onnx` → `export_coreml.py`)
- **Known gap**: trained before split-three/four pattern detection (added 2026-04-16) — CNN doesn't see gap attacks. Retrain recipe staged in `docs/retrain_plan.md` §A.

## Code structure

- `scenes/`, `scripts/` — Godot 4 client. Chinese-only UI (Noto Sans CJK SC subset bundled). AI levels L1-L4 in GDScript, L5/L6 via Swift plugin.
- `ios_plugin/Sources/` — Swift plugin: CoreML inference + MCTS. L5 = 1500 sims pattern-MCTS. L6 = 200 sims hybrid CNN+MCTS with 50/50 prior. Same plugin on iOS + macOS.
- `ai_server/` — Python training only (Mac). `nn/bootstrap.py` = Phase 1 (SL from pattern-MCTS teacher), `nn/iterate.py` = Phase 2 (self-play improvement).
- `docs/` — see Doc map below.

## Doc map

| Need | File |
|---|---|
| Algorithm reference (game logic, AI levels, MCTS, CNN) | `docs/technical_guide.md` |
| Training history + lessons + sweep results | `docs/ai_journey.md` (§1-§14) |
| Production retrain recipe + theory rationale | `docs/retrain_plan.md` |
| SOTA analysis (Rapfi) + improvement paths | `docs/gomoku_research.md` |
| Renju mode plan (UI + dispatch + retrain) | `docs/renju_plan.md` |
| Chronological dev log + recent recaps | `docs/dev_log.md` |

## GitHub
- Repo: github.com/jasonhorga/gomoku (**public** — was private originally, switched for unlimited GHA minutes for macOS notarization CI)
- SSH key: `~/.ssh/id_ed25519_hejia`
- Production branch: `main` (auto-merged from feature branches)
- **Push implication**: public + permanently archived (reflog + Copilot scrape). gitignore covers `.p8` / `AuthKey_*` / `.env*`. Diff-check for token-shaped strings before push.

## Working directory
**One repo, in Drive.** `/home/ubuntu/claude-web-data/hejia/gomoku/` is a real git checkout that syncs to Mac via Google Drive. Drive mount + git is fast (~70ms status). Build artifacts (`build/`, `.godot/`, `__pycache__/`) and runtime data (`game_records/`, `archive/`) are gitignored — local only on each machine.
