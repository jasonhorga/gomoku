"""Diagnostic: play ONE self-play game with full move logging.

Prints every move, the best attack vs defense score at each step, and
the final board state. Used to understand why games keep drawing.
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np
from ai.game_logic import GameLogic, BOARD_SIZE, BLACK, WHITE, EMPTY
from ai.mcts_engine import MCTSEngine
from ai.pattern_eval import score_cell, evaluate_position


def print_board(board):
    """Print 15x15 board with coordinates."""
    cols = "   " + " ".join(f"{c:2d}" for c in range(BOARD_SIZE))
    print(cols)
    for r in range(BOARD_SIZE):
        row_str = f"{r:2d} "
        for c in range(BOARD_SIZE):
            v = board[r][c]
            if v == BLACK:
                row_str += " X "
            elif v == WHITE:
                row_str += " O "
            else:
                row_str += " . "
        print(row_str)


def diag_one_game(sims=100, seed=42, verbose=True):
    np.random.seed(seed)
    import random
    random.seed(seed)

    game = GameLogic()
    mcts = MCTSEngine(
        simulations=sims,
        nn_model=None,
        use_pattern_prior=True,
        dirichlet_alpha=0.3,
        dirichlet_eps=0.25,
    )

    moves_log = []
    MAX_MOVES = 90
    while not game.game_over and len(game.move_history) < MAX_MOVES:
        player = game.current_player
        opp = WHITE if player == BLACK else BLACK

        # What are the top candidates and their attack/defense scores?
        candidates = game.get_nearby_moves(2)
        scored = []
        for r, c in candidates:
            atk = evaluate_position(game.board, r, c, player)
            dfd = evaluate_position(game.board, r, c, opp)
            total = score_cell(game.board, r, c, player)
            scored.append(((r, c), atk, dfd, total))
        scored.sort(key=lambda x: -x[3])

        # MCTS choice
        probs = mcts.get_move_probabilities(game)
        move_idx = int(np.argmax(probs))
        chosen = (move_idx // BOARD_SIZE, move_idx % BOARD_SIZE)

        if verbose:
            print(f"\n--- Move {len(game.move_history) + 1} "
                  f"({'BLACK' if player == BLACK else 'WHITE'}) ---")
            print(f"  Top-5 candidates (move, atk, def, total):")
            for i, (m, atk, dfd, tot) in enumerate(scored[:5]):
                marker = " <-- CHOSEN" if m == chosen else ""
                print(f"    {i+1}. {m}  atk={atk:8.0f}  def={dfd:8.0f}  "
                      f"total={tot:8.0f}{marker}")
            print(f"  MCTS picked: {chosen}")

        game.place_stone(chosen[0], chosen[1])
        moves_log.append((len(moves_log) + 1, player, chosen))

    print("\n" + "=" * 60)
    print(f"Game over. Winner={game.winner}, moves={len(game.move_history)}")
    print("=" * 60)
    print("\nFinal board:")
    print_board(game.board)

    print(f"\nMove sequence:")
    for idx, pl, (r, c) in moves_log:
        sym = "X" if pl == BLACK else "O"
        print(f"  {idx:3d}. {sym} ({r:2d},{c:2d})")


if __name__ == "__main__":
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("--sims", type=int, default=100)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--quiet", action="store_true", help="only show board")
    args = p.parse_args()
    diag_one_game(sims=args.sims, seed=args.seed, verbose=not args.quiet)
