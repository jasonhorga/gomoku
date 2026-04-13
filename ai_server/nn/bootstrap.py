"""Bootstrap (supervised) training pipeline.

Phase 1 of v2 training: a pattern-guided MCTS teacher plays against
itself to generate training data, then the CNN is trained by supervised
learning to imitate the teacher. Because the teacher is already competent
(Level-5 quality), this avoids the noise-amplification death spiral of
training RL from random initialization.

Pipeline:
  1. Parallel pattern-MCTS self-play -> raw samples
  2. 8x symmetry augmentation -> training set
  3. CNN training (Adam, cross-entropy policy + MSE value)
  4. Fixed-opponent evaluation: new CNN (used as MCTS prior) vs pattern-MCTS

Exits non-zero on smoke-test failure so the calling shell can abort.
"""

import argparse
import os
import sys
import time
import logging

sys.path.insert(0, os.path.dirname(os.path.abspath(os.path.dirname(__file__))))

from nn.augment import augment_dataset
from nn.parallel_self_play import run_parallel_self_play
from nn.trainer import Trainer
from nn.model import ModelWrapper
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


def evaluate_vs_opponent(model, teacher_sims, eval_games, logger,
                         eval_sims=None):
    """Play eval_games between CNN-guided MCTS and pattern-MCTS.

    Returns dict(win/lose/draw/win_rate).
    """
    if eval_sims is None:
        eval_sims = max(50, teacher_sims // 2)

    cnn_engine = MCTSEngine(simulations=eval_sims, nn_model=model,
                            use_pattern_prior=True)
    teacher_engine = MCTSEngine(simulations=teacher_sims, nn_model=None,
                                use_pattern_prior=True)

    wins = losses = draws = 0
    for i in range(eval_games):
        game = GameLogic()
        if i % 2 == 0:
            black_eng, white_eng = cnn_engine, teacher_engine
            cnn_color = BLACK
        else:
            black_eng, white_eng = teacher_engine, cnn_engine
            cnn_color = WHITE

        while not game.game_over:
            if game.current_player == BLACK:
                r, c = black_eng.choose_move(game)
            else:
                r, c = white_eng.choose_move(game)
            if not game.place_stone(r, c):
                break

        if game.winner == EMPTY:
            draws += 1
        elif game.winner == cnn_color:
            wins += 1
        else:
            losses += 1

        logger.info(f"  Eval {i+1}/{eval_games}: "
                    f"cnn={'B' if cnn_color == BLACK else 'W'} "
                    f"winner={'B' if game.winner == BLACK else ('W' if game.winner == WHITE else 'D')} "
                    f"moves={len(game.move_history)}")

    total = max(wins + losses + draws, 1)
    # Score = wins + 0.5 * draws (standard chess/board-game convention).
    # In gomoku without "forbidden moves" rule, two strong players often
    # draw, so "pure win rate" undercounts the learned strength.
    score = wins + 0.5 * draws
    return {
        "wins": wins,
        "losses": losses,
        "draws": draws,
        "win_rate": wins / total,
        "score_rate": score / total,
    }


def evaluate_vs_random(model, eval_games, logger):
    """Sanity check: CNN-MCTS vs random-move opponent. Must win ~100%."""
    import random as _random
    cnn_engine = MCTSEngine(simulations=50, nn_model=model,
                            use_pattern_prior=True)
    wins = 0
    for i in range(eval_games):
        game = GameLogic()
        cnn_color = BLACK if i % 2 == 0 else WHITE
        while not game.game_over:
            if game.current_player == cnn_color:
                r, c = cnn_engine.choose_move(game)
            else:
                cands = game.get_nearby_moves(2) or game.get_valid_moves()
                r, c = _random.choice(cands)
            if not game.place_stone(r, c):
                break
        if game.winner == cnn_color:
            wins += 1
    rate = wins / max(eval_games, 1)
    logger.info(f"  vs Random: {wins}/{eval_games} ({rate:.0%})")
    return rate


def bootstrap_train(args):
    logger = _setup_logger(args.log_file)
    logger.info("=" * 60)
    logger.info("  Bootstrap training (v2)")
    logger.info("  " + time.strftime("%Y-%m-%d %H:%M:%S"))
    logger.info("=" * 60)
    logger.info(f"Config: {vars(args)}")

    os.makedirs(WEIGHTS_DIR, exist_ok=True)

    # 1. Create fresh CNN
    logger.info(f"Creating CNN: {args.filters} filters, {args.blocks} blocks, "
                f"9 input channels")
    model = ModelWrapper(
        num_filters=args.filters,
        num_res_blocks=args.blocks,
        input_channels=9,
    )
    logger.info(f"  Parameters: {model.count_parameters():,}")
    logger.info(f"  Device: {model.device}")

    # 2. Self-play data generation
    logger.info(f"\n[1/4] Generating {args.games} self-play games "
                f"({args.simulations} MCTS sims, {args.workers} workers)...")
    t0 = time.time()
    total_winners = {BLACK: 0, WHITE: 0, EMPTY: 0}

    def progress(done, total, n, winner, moves, elapsed):
        total_winners[winner] += 1
        if done % max(1, total // 10) == 0 or done == total:
            logger.info(f"  game {done}/{total}: "
                        f"winner={'B' if winner == BLACK else ('W' if winner == WHITE else 'D')} "
                        f"moves={moves} samples={n} t={elapsed:.1f}s")

    raw_samples, selfplay_time, move_logs = run_parallel_self_play(
        num_games=args.games,
        simulations=args.simulations,
        num_workers=args.workers,
        use_9ch=True,
        on_progress=progress,
        record_first_n=min(4, args.games),  # record a few for inspection
    )
    logger.info(f"Self-play done: {len(raw_samples)} samples in {selfplay_time:.1f}s")
    logger.info(f"  Winners: B={total_winners[BLACK]} W={total_winners[WHITE]} "
                f"D={total_winners[EMPTY]}")

    # Dump recorded games to a text file next to the log
    if move_logs:
        games_path = os.path.join(
            LOG_DIR,
            (args.log_file or "bootstrap.log").replace(".log", "_games.txt"),
        )
        with open(games_path, "w") as f:
            for game_idx, winner, num_moves, log in move_logs:
                wchar = 'B' if winner == BLACK else ('W' if winner == WHITE else 'D')
                f.write(f"=== Game {game_idx} === winner={wchar} moves={num_moves}\n")
                for idx, pl, r, c in log:
                    sym = 'X' if pl == BLACK else 'O'
                    f.write(f"  {idx:3d}. {sym} ({r:2d},{c:2d})\n")
                f.write("\n")
        logger.info(f"  Recorded {len(move_logs)} sample games -> {games_path}")

    if len(raw_samples) < 100:
        logger.error("Too few samples generated. Check pattern-MCTS.")
        return 1

    # 3. Augmentation
    logger.info(f"\n[2/4] Augmenting 8x...")
    t0 = time.time()
    samples = augment_dataset(raw_samples)
    logger.info(f"  {len(raw_samples)} -> {len(samples)} samples in {time.time()-t0:.1f}s")

    # 4. Training
    logger.info(f"\n[3/4] Training: {args.epochs} epochs, batch={args.batch_size}, lr={args.lr}")
    trainer = Trainer(model, lr=args.lr)
    t0 = time.time()
    first_loss = None

    def on_epoch(epoch, total, loss):
        nonlocal first_loss
        if first_loss is None:
            first_loss = loss
        logger.info(f"  epoch {epoch}/{total}: loss={loss:.4f}")

    history = trainer.train_on_data(
        samples,
        epochs=args.epochs,
        batch_size=args.batch_size,
        on_progress=on_epoch,
    )
    t_train = time.time() - t0
    final_loss = history["total_loss"][-1]
    logger.info(f"Training done in {t_train:.1f}s. "
                f"Loss {first_loss:.4f} -> {final_loss:.4f}")

    # Did loss actually drop?
    loss_drop = (first_loss - final_loss) / max(first_loss, 1e-6)
    if loss_drop < 0.05:
        logger.warning(f"  Loss dropped only {loss_drop:.1%} - model may not be learning!")

    # 5. Evaluation
    logger.info(f"\n[4/4] Evaluation")

    # 5a. Sanity: vs random opponent
    logger.info("Sanity check: CNN-MCTS vs Random")
    random_rate = evaluate_vs_random(model, args.random_eval_games, logger)

    # 5b. Strength: vs pattern-MCTS teacher
    logger.info(f"Strength check: CNN-MCTS({args.simulations // 2}) "
                f"vs Pattern-MCTS({args.simulations})")
    teacher_result = evaluate_vs_opponent(
        model,
        teacher_sims=args.simulations,
        eval_games=args.eval_games,
        logger=logger,
    )
    logger.info(f"  vs Teacher: wins={teacher_result['wins']} "
                f"losses={teacher_result['losses']} "
                f"draws={teacher_result['draws']} "
                f"(win={teacher_result['win_rate']:.0%} "
                f"score={teacher_result['score_rate']:.0%})")

    # 6. Save model and training data
    save_name = args.save_name or f"bootstrap_{int(time.time())}.pt"
    save_path = os.path.join(WEIGHTS_DIR, save_name)
    model.save(save_path)
    logger.info(f"\nSaved model: {save_path}")

    # Save augmented samples so iterate.py can preload its replay buffer.
    # Prevents catastrophic forgetting in iteration 1 when fine-tune data
    # is much smaller than the bootstrap data.
    try:
        import pickle
        samples_path = save_path.replace(".pt", "_samples.pkl")
        # Only save raw samples (not augmented) to keep file small.
        # iterate.py can re-augment if needed.
        with open(samples_path, "wb") as f:
            pickle.dump(raw_samples, f, protocol=pickle.HIGHEST_PROTOCOL)
        logger.info(f"Saved training samples: {samples_path}")
    except Exception as e:
        logger.warning(f"Could not save samples: {e}")

    # 7. Verdict
    logger.info("\n" + "=" * 60)
    logger.info("  VERDICT")
    logger.info("=" * 60)
    verdict_lines = [
        f"  loss       : {first_loss:.4f} -> {final_loss:.4f}  ({loss_drop:.1%} drop)",
        f"  vs Random  : {random_rate:.0%}",
        f"  vs Teacher : {teacher_result['score_rate']:.0%} score  "
        f"({teacher_result['wins']}W {teacher_result['losses']}L "
        f"{teacher_result['draws']}D)",
        f"               (50% = equal, >55% = stronger than teacher)",
    ]
    for line in verdict_lines:
        logger.info(line)

    # Smoke test PASS criteria (focus on strong learning signals):
    #   - Loss dropped at least 15% (clear training progress)
    #   - vs Random win rate >= 80% (basic tactical competence)
    #
    # vs Teacher is logged but NOT a pass criterion at smoke-test scale:
    # with only 16 games of training data, the CNN policy is still flat,
    # and argmax over MCTS visit counts can look noisy. Full training
    # solves this. We just want to confirm the pipeline learns.
    if args.smoke:
        passed = (
            loss_drop >= 0.15 and
            random_rate >= 0.80
        )
        logger.info("")
        if passed:
            logger.info("  SMOKE TEST: PASS — strategy is working, scale up.")
            if teacher_result['win_rate'] < 0.10:
                logger.info("  (Note: vs Teacher is low but expected at this scale.")
                logger.info("   Full training has 6x more data and more epochs.)")
            return 0
        else:
            logger.info("  SMOKE TEST: FAIL — learning signal is weak.")
            logger.info("  Required: loss drop >=15%, vs Random >=80%")
            logger.info(f"  Got:      loss drop {loss_drop:.1%}, vs Random {random_rate:.0%}")
            return 2

    return 0


def main():
    p = argparse.ArgumentParser(description="v2 Bootstrap training pipeline")
    p.add_argument("--games", type=int, default=40, help="Self-play games")
    p.add_argument("--simulations", type=int, default=200, help="MCTS sims per move")
    p.add_argument("--workers", type=int, default=None, help="Parallel workers")
    p.add_argument("--epochs", type=int, default=30, help="Training epochs")
    p.add_argument("--batch-size", type=int, default=128)
    p.add_argument("--lr", type=float, default=1e-3)
    p.add_argument("--filters", type=int, default=32)
    p.add_argument("--blocks", type=int, default=2)
    p.add_argument("--eval-games", type=int, default=10, help="Games vs pattern-MCTS")
    p.add_argument("--random-eval-games", type=int, default=6)
    p.add_argument("--save-name", default=None, help="Output file name (in data/weights/)")
    p.add_argument("--log-file", default="bootstrap.log")
    p.add_argument("--smoke", action="store_true",
                   help="Enable smoke-test pass/fail semantics")
    args = p.parse_args()
    sys.exit(bootstrap_train(args))


if __name__ == "__main__":
    main()
