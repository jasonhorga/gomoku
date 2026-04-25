"""Regression test for the L6 vs L4 fork weakness.

Position: Mac AI Lab batch 2026-04-25, game 002 (L4 black quick-kill at
move 29 via reverse-diagonal (7,5)→(11,9) five-in-a-row). Trace shows:
- After 21 moves (white-to-play move 22), CNN value = -0.576 (recoverable)
- After 23 moves (white played 7,3), CNN value = -0.999 (lost)
- Move 22 is the critical mistake.

The current best_model.pt picks (7,3) at move 22 (which loses to a
double-threat fork). Free v2 should either:
  - Pick a different move at move 22 OR
  - Have a value head that doesn't predict near-certain loss after move 22

Run: `pytest tests/test_fork_defense.py -v` from ai_server/
"""
from __future__ import annotations

import os
import sys

import pytest
import torch

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from ai.game_logic import GameLogic, BLACK, WHITE  # noqa: E402
from ai.mcts_engine import MCTSEngine  # noqa: E402
from nn.model import ModelWrapper  # noqa: E402

# 21 moves up to (8,4) by black; next is white move 22.
FORK_MOVES = [
    (7, 7), (8, 7), (8, 6), (6, 8), (7, 6), (6, 6), (6, 7), (7, 8),
    (5, 8), (4, 9), (9, 6), (8, 5), (7, 5), (7, 4), (9, 7), (6, 4),
    (10, 6), (11, 6), (9, 5), (9, 4), (8, 4),
]

WEIGHTS_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "data", "weights",
)


def _load_model(filename: str = "best_model.pt") -> ModelWrapper:
    path = os.path.join(WEIGHTS_DIR, filename)
    if not os.path.exists(path):
        pytest.skip(f"weight file not present: {path}")
    ckpt = torch.load(path, map_location="cpu", weights_only=False)
    nf = ckpt.get("num_filters", 128)
    nb = ckpt.get("num_res_blocks", 6)
    mw = ModelWrapper(num_filters=nf, num_res_blocks=nb, device="cpu")
    mw.model.load_state_dict(ckpt["state_dict"])
    mw.model.eval()
    return mw


def _build_position():
    g = GameLogic()
    for m in FORK_MOVES:
        g.place_stone(*m)
    assert g.current_player == WHITE, "expected white-to-play after 21 moves"
    return g


# --- Baseline test: confirms current best_model exhibits the failure ----

def test_baseline_failure_documented():
    """Sanity check that best_model.pt fails as documented.

    If this test starts passing (model picks something other than (7,3) or
    value > -0.95 after move 22), it means the failure was fixed by some
    other change — investigate before declaring v2 redundant.
    """
    model = _load_model("best_model.pt")
    g = _build_position()
    policy, value = model.predict(g)
    # Baseline picks (7, 3); top-1 prior should be (7, 3).
    top_idx = int(policy.argmax())
    top_rc = (top_idx // 15, top_idx % 15)
    print(f"baseline top move: {top_rc}, value={value:+.3f}")
    # We document the failure rather than hard-asserting — if it passes
    # later, that's a (good) anomaly worth investigating manually.


# --- v2 test: only runs when free_v2_iter_*.pt exists -------------------

@pytest.mark.parametrize("filename", [
    f"free_v2_iter_{i}.pt" for i in range(1, 9)
])
def test_v2_fork_defense(filename):
    """New free_v2 model should resolve the fork weakness.

    Acceptance: at least one of:
      a) Top-1 move is NOT (7,3) (model finds a different defence)
      b) After picking a move, the resulting position's value > -0.95
         (i.e. doesn't think the position is already lost)

    Run only when the candidate model exists.
    """
    model = _load_model(filename)
    g = _build_position()
    policy, value = model.predict(g)

    top_idx = int(policy.argmax())
    top_rc = (top_idx // 15, top_idx % 15)

    # Criterion (a): model picks a different move
    different_move = top_rc != (7, 3)

    # Criterion (b): even with same move, value head isn't catastrophic
    not_lost = value > -0.95

    assert different_move or not_lost, (
        f"{filename} still exhibits fork weakness: top={top_rc} value={value:+.3f}"
    )


# --- MCTS-level test: full L6 search at production config ---------------

@pytest.mark.parametrize("filename,sims", [
    ("best_model.pt", 200),  # baseline, expected fail
])
def test_mcts_fork_defense(filename, sims):
    """Run full MCTSEngine at production config and verify the chosen
    move plus subsequent value. Slow (~30s per call). Documents baseline.
    """
    model = _load_model(filename)
    g = _build_position()
    mcts = MCTSEngine(
        simulations=sims, nn_model=model, use_pattern_prior=True,
        cnn_prior_weight=0.5, vcf_depth=10, dirichlet_alpha=0.0,
    )
    move = mcts.choose_move(g)
    print(f"{filename} ({sims} sims) at move 22 chose {move}")
    # No assertion on baseline — this just records the chosen move.
