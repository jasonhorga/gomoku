"""Benchmark two .pt models against each other.

Usage:
    python3 -m benchmark_models \
        --model-a data/weights/big_iter_3.pt \
        --model-b data/weights/bootstrap_128f6b.pt \
        --games 40 --sims 200 --filters 128 --blocks 6
"""
import argparse
import time

from nn.model import ModelWrapper
from nn.iterate import play_match
from ai.mcts_engine import MCTSEngine


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--model-a", required=True, help="Challenger .pt")
    p.add_argument("--model-b", required=True, help="Baseline .pt")
    p.add_argument("--games", type=int, default=40)
    p.add_argument("--sims", type=int, default=200)
    p.add_argument("--filters", type=int, default=128)
    p.add_argument("--blocks", type=int, default=6)
    p.add_argument("--vcf-depth", type=int, default=10)
    p.add_argument("--cnn-prior-weight", type=float, default=0.5)
    args = p.parse_args()

    print(f"Loading A: {args.model_a}")
    model_a = ModelWrapper(num_filters=args.filters,
                           num_res_blocks=args.blocks,
                           input_channels=9)
    model_a.load(args.model_a)

    print(f"Loading B: {args.model_b}")
    model_b = ModelWrapper(num_filters=args.filters,
                           num_res_blocks=args.blocks,
                           input_channels=9)
    model_b.load(args.model_b)

    eng_a = MCTSEngine(simulations=args.sims, nn_model=model_a,
                       use_pattern_prior=True, vcf_depth=args.vcf_depth,
                       cnn_prior_weight=args.cnn_prior_weight)
    eng_b = MCTSEngine(simulations=args.sims, nn_model=model_b,
                       use_pattern_prior=True, vcf_depth=args.vcf_depth,
                       cnn_prior_weight=args.cnn_prior_weight)

    print(f"Playing {args.games} games, {args.sims} sims each...")
    t0 = time.time()

    import logging
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    logger = logging.getLogger("bench")

    wins, losses, draws = play_match(eng_a, eng_b, args.games,
                                      logger=logger, label="bench")
    elapsed = time.time() - t0
    total = max(wins + losses + draws, 1)
    score = (wins + 0.5 * draws) / total

    print(f"\n{'='*60}")
    print(f"A={args.model_a}")
    print(f"B={args.model_b}")
    print(f"{wins}W {losses}L {draws}D  score={score:.1%}  ({elapsed:.1f}s)")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
