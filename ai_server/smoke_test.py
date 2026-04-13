#!/usr/bin/env python3
"""Fast smoke test for v2 training strategy.

Runs a tiny end-to-end bootstrap in 10-15 minutes on M-series Macs:
  - 16 self-play games × 100 MCTS sims × 3 workers
  - 8x symmetry augmentation
  - 20 training epochs, 32-filter 2-block CNN, 9-channel input
  - Eval vs random (sanity) and vs pattern-MCTS (strength)

PASS criteria:
  - Training loss drops >= 15%
  - Win rate vs Random >= 90%
  - Win rate vs Pattern-MCTS >= 20%  (some learning signal)

If smoke test PASSES, we proceed with full bootstrap (see run_full_training_v2.sh).
If it FAILS, we need to rethink rather than burn another overnight run.
"""

import os
import sys

# Ensure ai_server root is on path
_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
if _THIS_DIR not in sys.path:
    sys.path.insert(0, _THIS_DIR)

from nn.bootstrap import bootstrap_train
import argparse


def main():
    # Hard-coded small values so the user just runs `python smoke_test.py`
    args = argparse.Namespace(
        games=16,
        simulations=100,
        workers=3,
        epochs=20,
        batch_size=128,
        lr=1e-3,
        filters=32,
        blocks=2,
        eval_games=6,
        random_eval_games=6,
        save_name="smoke_test.pt",
        log_file="smoke_test.log",
        smoke=True,
    )
    sys.exit(bootstrap_train(args))


if __name__ == "__main__":
    main()
