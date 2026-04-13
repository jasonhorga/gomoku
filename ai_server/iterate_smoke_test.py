"""Quick sanity check for the iteration loop.

Uses the smoke_test.pt bootstrap checkpoint as π_0 and runs 2 tiny
iterations of 4 games each. Expected runtime ~10 minutes on M5 CPU.
Looks for: loss drops, iter_1 beats iter_0, iter_2 beats iter_1.
"""
import os
import sys
import argparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nn.iterate import iterate_train


def main():
    initial = os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        "data", "weights", "smoke_test.pt"
    )
    if not os.path.exists(initial):
        print(f"ERROR: bootstrap checkpoint not found at {initial}")
        print("Run smoke_test.py first to create it.")
        sys.exit(1)

    args = argparse.Namespace(
        initial_model=initial,
        iterations=2,
        games_per_iter=4,
        simulations=80,
        epochs=6,                  # fewer epochs to avoid overfit on small batch
        batch_size=128,
        lr=2e-4,                   # lower LR (don't destroy bootstrap weights)
        replay_size=6000,          # larger buffer (bootstrap data + new games)
        filters=32,
        blocks=2,
        vcf_depth=6,
        benchmark_games=6,
        benchmark_sims=60,
        converge_threshold=0.50,   # relaxed for smoke test
        log_file="iterate_smoke.log",
    )
    sys.exit(iterate_train(args))


if __name__ == "__main__":
    main()
