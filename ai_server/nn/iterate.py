"""Iterative self-play training (AlphaZero-style policy improvement).

Phase 2 of v2 training. After bootstrap gives us π_0 ≈ pattern+VCF teacher,
this module runs the iteration loop:

  for i in 1..N:
    generate self-play games using CNN_{i-1} + MCTS + VCF
    fine-tune CNN on those games -> CNN_i
    benchmark CNN_i vs CNN_{i-1}
    stop if CNN_i is not measurably stronger

The mechanism: MCTS amplifies whatever CNN knows. Training CNN to imitate
MCTS(CNN) makes CNN learn what search discovered. Each iteration raises
both CNN and MCTS(CNN) strictly. This is AlphaZero's Policy Improvement
step, not pure distillation.

Why this is safer than v1's iterative self-play:
  - π_0 already has Level-5+ competence from bootstrap
  - Each iteration benchmarks vs the previous; we abort if no improvement
  - Replay buffer keeps older games to prevent catastrophic forgetting
"""

import argparse
import os
import sys
import time
import logging

sys.path.insert(0, os.path.dirname(os.path.abspath(os.path.dirname(__file__))))

import numpy as np
import random

from nn.augment import augment_dataset
from nn.trainer import Trainer
from nn.model import ModelWrapper
from nn.parallel_self_play import _random_opening, _sample_move
from ai.game_logic import GameLogic, BOARD_SIZE, BLACK, WHITE, EMPTY
from ai.mcts_engine import MCTSEngine


WEIGHTS_DIR = os.path.join(
    os.path.dirname(os.path.abspath(os.path.dirname(__file__))),
    'data', 'weights'
)
LOG_DIR = os.path.join(
    os.path.dirname(os.path.abspath(os.path.dirname(__file__))),
    'logs'
)


def _setup_logger(log_file):
    os.makedirs(LOG_DIR, exist_ok=True)
    handlers = [logging.StreamHandler()]
    if log_file:
        handlers.append(logging.FileHandler(os.path.join(LOG_DIR, log_file)))
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s [%(levelname)s] %(message)s',
        handlers=handlers,
        force=True,
    )
    return logging.getLogger(__name__)


def _winner_char(w):
    return 'B' if w == BLACK else ('W' if w == WHITE else 'D')


# --------------------------------------------------------------------------
# Self-play with a CNN-guided engine (sequential; models don't pickle cleanly)
# --------------------------------------------------------------------------

def play_game_cnn(model, simulations, seed=None, vcf_depth=6,
                  random_opening_plies=4, max_moves=100,
                  cnn_prior_weight=0.5):
    """Play one self-play game with CNN-guided MCTS.

    The model provides priors and leaf values; MCTS explores; VCF handles
    forced tactical wins. Dirichlet noise ensures diversity. Returns
    (samples, winner, num_moves) where samples is a list of
    (tensor, probs, value) triples.
    """
    if seed is not None:
        np.random.seed(seed)
        random.seed(seed)

    game = GameLogic()
    _random_opening(game, num_plies=random_opening_plies)

    mcts = MCTSEngine(
        simulations=simulations,
        nn_model=model,
        use_pattern_prior=True,
        dirichlet_alpha=0.3,
        dirichlet_eps=0.25,
        vcf_depth=vcf_depth,
        cnn_prior_weight=cnn_prior_weight,
    )

    history = []
    while not game.game_over and len(game.move_history) < max_moves:
        probs = mcts.get_move_probabilities(game)
        tensor = game.to_tensor_9ch(game.current_player)
        history.append((tensor, probs.copy(), game.current_player))

        move_idx = _sample_move(probs, len(game.move_history))
        row, col = move_idx // BOARD_SIZE, move_idx % BOARD_SIZE
        if not game.place_stone(row, col):
            valid = game.get_valid_moves()
            if not valid:
                break
            row, col = valid[0]
            game.place_stone(row, col)

    samples = []
    for tensor, probs, player in history:
        if game.winner == EMPTY:
            value = 0.0
        elif game.winner == player:
            value = 1.0
        else:
            value = -1.0
        samples.append((tensor, probs, value))

    return samples, game.winner, len(history)


# --------------------------------------------------------------------------
# Head-to-head match between two engines
# --------------------------------------------------------------------------

def play_match(engine_a, engine_b, num_games, logger=None, label=""):
    """Play num_games between engine_a and engine_b. Alternating colors.

    Returns (a_wins, b_wins, draws). No noise, deterministic.
    """
    a_wins = b_wins = draws = 0
    for i in range(num_games):
        game = GameLogic()
        if i % 2 == 0:
            black, white = engine_a, engine_b
            a_is_black = True
        else:
            black, white = engine_b, engine_a
            a_is_black = False

        while not game.game_over and len(game.move_history) < 150:
            if game.current_player == BLACK:
                r, c = black.choose_move(game)
            else:
                r, c = white.choose_move(game)
            if not game.place_stone(r, c):
                break

        if game.winner == EMPTY:
            draws += 1
        elif (game.winner == BLACK) == a_is_black:
            a_wins += 1
        else:
            b_wins += 1

        if logger:
            logger.info(f"  {label} game {i+1}/{num_games}: "
                        f"a={'B' if a_is_black else 'W'} "
                        f"winner={_winner_char(game.winner)} "
                        f"moves={len(game.move_history)}")
    return a_wins, b_wins, draws


# --------------------------------------------------------------------------
# Single iteration
# --------------------------------------------------------------------------

def run_one_iteration(model, iter_idx, args, bootstrap_pool, fresh_pool, logger):
    """Run one self-play + fine-tune iteration.

    Uses a two-pool replay buffer: bootstrap_pool is fixed (never evicted,
    preserves pattern+VCF teacher knowledge), fresh_pool is FIFO of CNN
    self-play samples. Training data = bootstrap_pool + fresh_pool.

    Without this split, the FIFO was overwriting ALL bootstrap samples
    with fresh CNN self-play data (because one iter's augmented samples
    exceed replay_size), causing catastrophic forgetting and iter_1
    regressing to 40% vs iter_0.

    Mutates model in-place. Returns (first_loss, final_loss, num_fresh).
    """
    logger.info(f"\n{'='*60}")
    logger.info(f"  Iteration {iter_idx}/{args.iterations}")
    logger.info(f"{'='*60}")

    # --- Self-play --------------------------------------------------
    logger.info(f"[{iter_idx}a] Self-play: {args.games_per_iter} games, "
                f"{args.simulations} sims, CNN priors")
    raw = []
    winners = {BLACK: 0, WHITE: 0, EMPTY: 0}
    t0 = time.time()
    for g in range(args.games_per_iter):
        samples, winner, moves = play_game_cnn(
            model,
            simulations=args.simulations,
            seed=iter_idx * 10007 + g,
            vcf_depth=args.vcf_depth,
            cnn_prior_weight=getattr(args, 'cnn_prior_weight', 0.5),
        )
        raw.extend(samples)
        winners[winner] += 1
        logger.info(f"  iter{iter_idx} game {g+1}/{args.games_per_iter}: "
                    f"winner={_winner_char(winner)} moves={moves} "
                    f"samples={len(samples)}")
    sp_elapsed = time.time() - t0
    logger.info(f"  self-play done: {len(raw)} raw samples in "
                f"{sp_elapsed:.1f}s (B={winners[BLACK]} W={winners[WHITE]} "
                f"D={winners[EMPTY]})")

    if len(raw) < 20:
        logger.error("  too few samples, skipping fine-tune for this iter")
        return None, None, 0

    # --- Augment ----------------------------------------------------
    logger.info(f"[{iter_idx}b] Augmenting 8x")
    fresh = augment_dataset(raw)
    logger.info(f"  {len(raw)} -> {len(fresh)} samples")

    # --- Fresh pool (FIFO, bootstrap_pool is separate and never evicted)
    # Cap fresh at bootstrap size so teacher knowledge stays >= 50% of
    # training data.  Without this cap, one iter's 22k fresh samples
    # dominate the 18k bootstrap anchor and the model drifts toward
    # lower-quality self-play data.
    fresh_pool.extend(fresh)
    fr = getattr(args, 'fresh_ratio', 1.0)
    if len(bootstrap_pool) == 0:
        fresh_cap = args.replay_size
    else:
        fresh_cap = min(
            max(args.replay_size - len(bootstrap_pool), len(fresh)),
            int(len(bootstrap_pool) * fr),
        )
    if len(fresh_pool) > fresh_cap:
        fresh_pool[:] = fresh_pool[-fresh_cap:]
    logger.info(f"  bootstrap pool: {len(bootstrap_pool)} (fixed)")
    logger.info(f"  fresh pool: {len(fresh_pool)} (FIFO, cap {fresh_cap})")

    # Training data is the union — bootstrap is anchor, fresh adds new signal
    training_data = bootstrap_pool + fresh_pool
    logger.info(f"  training data: {len(training_data)} samples "
                f"({len(bootstrap_pool)} anchor + {len(fresh_pool)} fresh)")

    # --- Fine-tune --------------------------------------------------
    logger.info(f"[{iter_idx}c] Fine-tune: {args.epochs} epochs, lr={args.lr}")
    trainer = Trainer(model, lr=args.lr)
    first_loss = None

    def on_epoch(e, t, l):
        nonlocal first_loss
        if first_loss is None:
            first_loss = l
        logger.info(f"  epoch {e}/{t}: loss={l:.4f}")

    history = trainer.train_on_data(
        training_data,
        epochs=args.epochs,
        batch_size=args.batch_size,
        on_progress=on_epoch,
    )
    final_loss = history["total_loss"][-1]
    logger.info(f"  loss {first_loss:.4f} -> {final_loss:.4f}")

    return first_loss, final_loss, len(fresh)


# --------------------------------------------------------------------------
# Top-level iteration loop
# --------------------------------------------------------------------------

def iterate_train(args):
    logger = _setup_logger(args.log_file)
    logger.info("=" * 60)
    logger.info("  Iterative self-play training (v2 Phase 2)")
    logger.info("  " + time.strftime("%Y-%m-%d %H:%M:%S"))
    logger.info("=" * 60)
    logger.info(f"Config: {vars(args)}")

    os.makedirs(WEIGHTS_DIR, exist_ok=True)

    # --- Load starting model -------------------------------------
    if not os.path.exists(args.initial_model):
        logger.error(f"Initial model not found: {args.initial_model}")
        logger.error("Run bootstrap training first to create it.")
        return 1

    model = ModelWrapper(
        num_filters=args.filters,
        num_res_blocks=args.blocks,
        input_channels=9,
    )
    model.load(args.initial_model)
    logger.info(f"Loaded π_0 from {args.initial_model}")
    logger.info(f"  Parameters: {model.count_parameters():,}")
    logger.info(f"  Device: {model.device}")

    # Two-pool replay buffer: bootstrap samples are the anchor (never
    # evicted), fresh samples accumulate FIFO. Training uses union of
    # both. This prevents the catastrophic-forgetting regression we saw
    # in full training where one iter's 22k fresh augmented samples
    # evicted ALL bootstrap data from a 20k FIFO buffer.
    bootstrap_pool = []
    fresh_pool = []

    samples_path = args.initial_model.replace(".pt", "_samples.pkl")
    if os.path.exists(samples_path):
        import pickle
        with open(samples_path, "rb") as f:
            bootstrap_raw = pickle.load(f)
        logger.info(f"Loading bootstrap samples: {samples_path}")
        bootstrap_aug = augment_dataset(bootstrap_raw)
        # Cap bootstrap pool at 60% of replay_size to leave room for fresh.
        boot_cap = max(args.replay_size * 6 // 10, 4000)
        if len(bootstrap_aug) > boot_cap:
            idxs = np.random.choice(len(bootstrap_aug), boot_cap, replace=False)
            bootstrap_aug = [bootstrap_aug[i] for i in idxs]
        bootstrap_pool = bootstrap_aug
        logger.info(f"  Bootstrap anchor pool: {len(bootstrap_pool)} samples "
                    f"(fixed, never evicted)")
    else:
        logger.warning(f"No bootstrap samples at {samples_path}")
        logger.warning("  Iteration 1 will overfit on fresh games only. "
                       "Re-run bootstrap to save samples.")

    prev_path = args.initial_model

    # Track convergence
    convergence_history = []  # list of (iter, score_rate)

    for iter_idx in range(1, args.iterations + 1):
        result = run_one_iteration(model, iter_idx, args,
                                    bootstrap_pool, fresh_pool, logger)
        if result[0] is None:
            logger.info("Skipping benchmark due to empty iteration")
            continue
        first_loss, final_loss, n_fresh = result

        # Save this iteration's checkpoint
        pfx = getattr(args, 'checkpoint_prefix', '')
        save_name = f"{pfx}iter_{iter_idx}.pt"
        save_path = os.path.join(WEIGHTS_DIR, save_name)
        model.save(save_path)
        logger.info(f"  saved {save_path}")

        # --- Benchmark vs previous iteration -----------------------
        logger.info(f"[{iter_idx}d] Benchmark: π_{iter_idx} vs π_{iter_idx-1}")
        prev_model = ModelWrapper(
            num_filters=args.filters,
            num_res_blocks=args.blocks,
            input_channels=9,
        )
        prev_model.load(prev_path)

        cpw = getattr(args, 'cnn_prior_weight', 0.5)
        cur_engine = MCTSEngine(
            simulations=args.benchmark_sims,
            nn_model=model,
            use_pattern_prior=True,
            vcf_depth=args.vcf_depth,
            cnn_prior_weight=cpw,
        )
        prev_engine = MCTSEngine(
            simulations=args.benchmark_sims,
            nn_model=prev_model,
            use_pattern_prior=True,
            vcf_depth=args.vcf_depth,
            cnn_prior_weight=cpw,
        )

        t0 = time.time()
        wins, losses, draws = play_match(
            cur_engine, prev_engine, args.benchmark_games,
            logger=logger, label=f"iter{iter_idx}vs{iter_idx-1}"
        )
        bench_elapsed = time.time() - t0
        total = max(wins + losses + draws, 1)
        score = (wins + 0.5 * draws) / total
        logger.info(f"  iter{iter_idx} vs iter{iter_idx-1}: "
                    f"{wins}W {losses}L {draws}D  score={score:.0%}  "
                    f"({bench_elapsed:.1f}s)")

        convergence_history.append((iter_idx, score))

        # --- Convergence check --------------------------------------
        if score < args.converge_threshold:
            logger.info(f"\nConvergence: score < {args.converge_threshold:.0%} "
                        f"at iteration {iter_idx}. Stopping.")
            pfx = getattr(args, 'checkpoint_prefix', '')
            logger.info(f"Best checkpoint: {pfx}iter_{iter_idx - 1 if score < 0.5 else iter_idx}.pt")
            break

        prev_path = save_path
        # Free previous model so we don't leak memory
        del prev_model

    # --- Final summary -----------------------------------------------
    logger.info("\n" + "=" * 60)
    logger.info("  ITERATION SUMMARY")
    logger.info("=" * 60)
    for i, s in convergence_history:
        logger.info(f"  iter{i} vs iter{i-1}: {s:.0%}")

    if convergence_history:
        last_iter, last_score = convergence_history[-1]
        if last_score >= args.converge_threshold:
            logger.info(f"  Finished all {args.iterations} iterations without "
                        f"convergence — may benefit from more.")
        pfx = getattr(args, 'checkpoint_prefix', '')
        final = last_iter if last_score >= 0.5 else last_iter - 1
        logger.info(f"  RECOMMENDED: {pfx}iter_{final}.pt")
    return 0


def main():
    p = argparse.ArgumentParser(description="v2 Phase 2: iterative self-play")
    p.add_argument("--initial-model", required=True,
                   help="Path to bootstrap checkpoint (e.g. data/weights/bootstrap.pt)")
    p.add_argument("--iterations", type=int, default=3,
                   help="Max number of iterations")
    p.add_argument("--games-per-iter", type=int, default=50)
    p.add_argument("--simulations", type=int, default=200,
                   help="MCTS sims per move during self-play")
    p.add_argument("--epochs", type=int, default=15,
                   help="Fine-tune epochs per iteration")
    p.add_argument("--batch-size", type=int, default=128)
    p.add_argument("--lr", type=float, default=2e-4,
                   help="Fine-tune LR (much lower than bootstrap to avoid destroying weights)")
    p.add_argument("--replay-size", type=int, default=8000,
                   help="Max samples in replay buffer")
    p.add_argument("--filters", type=int, default=32)
    p.add_argument("--blocks", type=int, default=2)
    p.add_argument("--vcf-depth", type=int, default=6)
    p.add_argument("--benchmark-games", type=int, default=20)
    p.add_argument("--benchmark-sims", type=int, default=100)
    p.add_argument("--converge-threshold", type=float, default=0.55,
                   help="Stop when new model scores <X vs previous")
    p.add_argument("--cnn-prior-weight", type=float, default=0.5,
                   help="CNN vs pattern prior blend (0=all pattern, 1=all CNN)")
    p.add_argument("--fresh-ratio", type=float, default=1.0,
                   help="Max fresh pool size as multiple of bootstrap pool")
    p.add_argument("--checkpoint-prefix", default="",
                   help="Prefix for checkpoint filenames (e.g. 'phA_')")
    p.add_argument("--log-file", default="iterate.log")
    args = p.parse_args()
    sys.exit(iterate_train(args))


if __name__ == "__main__":
    main()
