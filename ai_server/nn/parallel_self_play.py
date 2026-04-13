"""Parallel self-play data generation using pattern-guided MCTS.

Uses multiprocessing.Pool to run several games concurrently. Each worker
runs pure NumPy/Python (no GPU contention), and the pattern-guided MCTS
is strong enough to generate Level-5-quality training data without needing
a neural net at all.

This is the foundation of the v2 bootstrap: the CNN learns to imitate a
competent MCTS teacher, instead of bootstrapping from random noise.
"""

import os
import sys
import time
import multiprocessing as mp
import numpy as np

# Ensure the ai_server root is on the path for workers
_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.dirname(_THIS_DIR)
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)

from ai.game_logic import GameLogic, BOARD_SIZE, BLACK, WHITE, EMPTY
from ai.mcts_engine import MCTSEngine


def _sample_move(probs: np.ndarray, move_count: int) -> int:
    """Temperature-controlled move sampling."""
    if move_count < 8:
        temp = 1.0  # early game: exploration
    elif move_count < 16:
        temp = 0.5
    else:
        temp = 0.1  # late game: exploit

    if temp < 0.01:
        return int(np.argmax(probs))

    probs_t = np.power(probs, 1.0 / temp)
    total = probs_t.sum()
    if total <= 0:
        nonzero = np.where(probs > 0)[0]
        if len(nonzero) == 0:
            return 0
        return int(np.random.choice(nonzero))
    probs_t = probs_t / total
    return int(np.random.choice(len(probs_t), p=probs_t))


def _random_opening(game: GameLogic, num_plies: int = 4):
    """Play a few random opening moves near the center to diversify games.

    Without this, every self-play game converges to the same main line
    because pattern-MCTS picks the same move for a given board. The first
    move is always the center; subsequent moves are uniformly sampled
    from a radius-2 neighborhood of existing stones.
    """
    import random
    if num_plies <= 0:
        return
    # First stone: center
    game.place_stone(BOARD_SIZE // 2, BOARD_SIZE // 2)
    for _ in range(num_plies - 1):
        if game.game_over:
            return
        cands = game.get_nearby_moves(2)
        if not cands:
            return
        r, c = random.choice(cands)
        game.place_stone(r, c)


def play_one_game(simulations: int, seed: int = None, use_9ch: bool = True,
                   record_moves: bool = False, random_opening_plies: int = 4):
    """Play a single self-play game with pattern-MCTS.

    Returns (samples, winner, num_moves[, move_log]) where move_log is
    included only if record_moves=True.
    """
    if seed is not None:
        np.random.seed(seed)
        import random
        random.seed(seed)

    game = GameLogic()

    # Random opening for diversity. Without it, all 16 games in a batch
    # would visit almost-identical states.
    _random_opening(game, num_plies=random_opening_plies)

    mcts = MCTSEngine(
        simulations=simulations,
        nn_model=None,
        use_pattern_prior=True,
        dirichlet_alpha=0.3,
        dirichlet_eps=0.25,
        vcf_depth=6,
    )
    history = []  # list of (tensor, probs, player)
    move_log = [] if record_moves else None  # list of (idx, player, r, c)

    # Hard cap on game length: most games with VCF resolve under 80
    # moves; anything past 100 is almost certainly a positional draw.
    MAX_MOVES = 100

    # Capture the opening moves in the log
    if record_moves:
        for idx, mv in enumerate(game.move_history):
            # mv may be Vector2i-like or (r, c) tuple
            if hasattr(mv, 'x') and hasattr(mv, 'y'):
                r, c = mv.x, mv.y
            else:
                r, c = mv
            pl = BLACK if idx % 2 == 0 else WHITE
            move_log.append((idx + 1, pl, int(r), int(c)))

    while not game.game_over and len(game.move_history) < MAX_MOVES:
        probs = mcts.get_move_probabilities(game)

        if use_9ch:
            tensor = game.to_tensor_9ch(game.current_player)
        else:
            tensor = game.to_tensor(game.current_player)
        history.append((tensor, probs.copy(), game.current_player))

        move_idx = _sample_move(probs, len(game.move_history))
        row, col = move_idx // BOARD_SIZE, move_idx % BOARD_SIZE
        player_before = game.current_player

        if not game.place_stone(row, col):
            valid = game.get_valid_moves()
            if not valid:
                break
            row, col = valid[0]
            game.place_stone(row, col)

        if record_moves:
            move_log.append((len(game.move_history), player_before,
                             int(row), int(col)))

    # Assign values
    data = []
    for tensor, probs, player in history:
        if game.winner == EMPTY:
            value = 0.0
        elif game.winner == player:
            value = 1.0
        else:
            value = -1.0
        data.append((tensor, probs, value))

    if record_moves:
        return data, game.winner, len(history), move_log
    return data, game.winner, len(history)


def _worker(args):
    game_idx, simulations, seed, use_9ch, record_moves = args
    t0 = time.time()
    if record_moves:
        data, winner, moves, move_log = play_one_game(
            simulations, seed=seed, use_9ch=use_9ch, record_moves=True
        )
    else:
        data, winner, moves = play_one_game(
            simulations, seed=seed, use_9ch=use_9ch
        )
        move_log = None
    elapsed = time.time() - t0
    return game_idx, data, winner, moves, elapsed, move_log


def run_parallel_self_play(num_games: int, simulations: int = 200,
                           num_workers: int = None, use_9ch: bool = True,
                           on_progress=None, record_first_n: int = 0):
    """Run self-play across multiple processes.

    record_first_n: save move logs for the first N games (for inspection).

    Returns (samples, total_elapsed, move_logs) where move_logs is a list
    of up to record_first_n (game_idx, winner, moves, log) tuples.
    """
    if num_workers is None:
        num_workers = max(1, min(4, (os.cpu_count() or 2) - 1))

    # Prepare jobs — first N jobs request move recording
    base_seed = int(time.time()) & 0xFFFF
    jobs = [(i, simulations, base_seed + i * 131, use_9ch,
             i < record_first_n) for i in range(num_games)]

    all_data = []
    move_logs = []
    t_start = time.time()

    if num_workers <= 1:
        # Sequential fallback (easier to debug)
        for job in jobs:
            i, data, winner, moves, elapsed, log = _worker(job)
            all_data.extend(data)
            if log is not None:
                move_logs.append((i, winner, moves, log))
            if on_progress:
                on_progress(i + 1, num_games, len(data), winner, moves, elapsed)
    else:
        with mp.Pool(processes=num_workers) as pool:
            done = 0
            for result in pool.imap_unordered(_worker, jobs):
                i, data, winner, moves, elapsed, log = result
                all_data.extend(data)
                if log is not None:
                    move_logs.append((i, winner, moves, log))
                done += 1
                if on_progress:
                    on_progress(done, num_games, len(data), winner, moves, elapsed)

    total_elapsed = time.time() - t_start
    return all_data, total_elapsed, move_logs


if __name__ == "__main__":
    # Smoke test for the module
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("--games", type=int, default=4)
    p.add_argument("--sims", type=int, default=100)
    p.add_argument("--workers", type=int, default=2)
    args = p.parse_args()

    def progress(done, total, n, winner, moves, elapsed):
        print(f"  game {done}/{total}: winner={winner} moves={moves} "
              f"samples={n} time={elapsed:.1f}s")

    data, elapsed = run_parallel_self_play(
        args.games, simulations=args.sims, num_workers=args.workers,
        on_progress=progress
    )
    print(f"Generated {len(data)} samples in {elapsed:.1f}s")
