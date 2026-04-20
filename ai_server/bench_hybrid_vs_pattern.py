"""Quick cross-check: does the CNN actually help L6?

If the Swift port or CoreML conversion was silently corrupting inference,
we'd see hybrid (pattern+CNN) perform at or below pattern-only strength.
If training itself is the bottleneck, we'd see hybrid modestly above
pattern-only but still beatable by a human.

Runs an even-games match with colour alternation.
"""
import argparse
import sys
import time

from ai.game_logic import GameLogic, BLACK, WHITE
from ai.mcts_engine import MCTSEngine
from nn.model import ModelWrapper


def play_game(black_engine, white_engine, max_moves=225):
    game = GameLogic()
    move_idx = 0
    while not game.game_over and move_idx < max_moves:
        engine = black_engine if game.current_player == BLACK else white_engine
        r, c = engine.choose_move(game)
        if not game.place_stone(r, c):
            # Defensive: illegal move → treat as loss for that side.
            return 2 if game.current_player == BLACK else 1
        move_idx += 1
    return int(game.winner)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--model", default="data/weights/best_model.pt")
    p.add_argument("--games", type=int, default=20)
    p.add_argument("--sims", type=int, default=200)
    p.add_argument("--filters", type=int, default=128)
    p.add_argument("--blocks", type=int, default=6)
    args = p.parse_args()

    print(f"Loading {args.model}…")
    nn = ModelWrapper(num_filters=args.filters, num_res_blocks=args.blocks,
                      input_channels=9)
    nn.load(args.model)

    hybrid = MCTSEngine(simulations=args.sims, nn_model=nn,
                        use_pattern_prior=True, cnn_prior_weight=0.5,
                        vcf_depth=10, dirichlet_alpha=0.0)
    pattern_only = MCTSEngine(simulations=args.sims, nn_model=None,
                              use_pattern_prior=True, vcf_depth=10,
                              dirichlet_alpha=0.0)

    hybrid_score = 0.0
    pattern_score = 0.0
    draws = 0
    t0 = time.time()

    for i in range(args.games):
        # Alternate colours so neither side gets a deterministic advantage.
        if i % 2 == 0:
            black, white = hybrid, pattern_only
            b_label, w_label = "hybrid", "pattern"
        else:
            black, white = pattern_only, hybrid
            b_label, w_label = "pattern", "hybrid"

        winner = play_game(black, white)
        if winner == BLACK:
            if b_label == "hybrid":
                hybrid_score += 1
            else:
                pattern_score += 1
        elif winner == WHITE:
            if w_label == "hybrid":
                hybrid_score += 1
            else:
                pattern_score += 1
        else:
            draws += 1
            hybrid_score += 0.5
            pattern_score += 0.5

        done = i + 1
        print(f"[{done}/{args.games}] {b_label}({'B' if winner==BLACK else 'L' if winner!=0 else 'D'})"
              f" vs {w_label}({'W' if winner==WHITE else 'L' if winner!=0 else 'D'}) "
              f"| hybrid={hybrid_score:.1f} pattern={pattern_score:.1f} draws={draws}",
              flush=True)

    dt = time.time() - t0
    print(f"\n== {args.games} games in {dt:.0f}s ==")
    print(f"hybrid : {hybrid_score:.1f} / {args.games} "
          f"({100 * hybrid_score / args.games:.1f}%)")
    print(f"pattern: {pattern_score:.1f} / {args.games} "
          f"({100 * pattern_score / args.games:.1f}%)")
    print(f"draws  : {draws}")


if __name__ == "__main__":
    sys.exit(main())
