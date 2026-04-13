#!/usr/bin/env python3
"""
Training pipeline for Gomoku AI.
Run on MacBook: python train_pipeline.py --generations 10

Each generation:
  1. Self-play N games using current model + MCTS
  2. Train CNN on collected data
  3. Evaluate: new model vs old model
  4. Keep new model if it wins > 55%
"""

import argparse
import os
import sys
import time
import logging

# Add parent to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler(os.path.join(os.path.dirname(__file__), 'logs', 'training.log')),
    ]
)
logger = logging.getLogger(__name__)

WEIGHTS_DIR = os.path.join(os.path.dirname(__file__), 'data', 'weights')


def train(args):
    # Lazy imports so --help works without torch
    from nn.model import ModelWrapper
    from nn.self_play import run_self_play
    from nn.trainer import Trainer
    from ai.game_logic import GameLogic, BLACK, WHITE, EMPTY
    from ai.mcts_engine import MCTSEngine

    os.makedirs(WEIGHTS_DIR, exist_ok=True)
    os.makedirs(os.path.join(os.path.dirname(__file__), 'logs'), exist_ok=True)

    # Load or create model
    model = ModelWrapper(num_filters=args.filters, num_res_blocks=args.blocks)
    weight_files = sorted([f for f in os.listdir(WEIGHTS_DIR) if f.endswith('.pt')])

    if weight_files:
        latest = os.path.join(WEIGHTS_DIR, weight_files[-1])
        model.load(latest)
        start_gen = len(weight_files)
        logger.info(f"Loaded weights: {weight_files[-1]} (generation {start_gen})")
    else:
        start_gen = 0
        # Save initial random weights as gen 0
        path = os.path.join(WEIGHTS_DIR, 'gen_000.pt')
        model.save(path)
        logger.info("Starting from random initialization (gen 0)")

    for gen in range(start_gen, start_gen + args.generations):
        logger.info(f"\n{'='*50}")
        logger.info(f"Generation {gen + 1}")
        logger.info(f"{'='*50}")

        # 1. Self-play
        logger.info(f"Self-play: {args.games} games, {args.simulations} MCTS sims each...")
        t0 = time.time()

        def on_self_play_progress(done, total, data_len):
            if done % 5 == 0 or done == total:
                logger.info(f"  Self-play: {done}/{total} games ({data_len} samples)")

        training_data = run_self_play(
            model, args.games, args.simulations, on_progress=on_self_play_progress
        )
        t_selfplay = time.time() - t0
        logger.info(f"Self-play done: {len(training_data)} samples in {t_selfplay:.1f}s")

        # 2. Train
        logger.info(f"Training: {args.epochs} epochs...")
        trainer = Trainer(model, lr=args.lr)
        t0 = time.time()

        def on_train_progress(epoch, total, loss):
            logger.info(f"  Epoch {epoch}/{total}: loss={loss:.4f}")

        history = trainer.train_on_data(
            training_data, epochs=args.epochs, batch_size=args.batch_size,
            on_progress=on_train_progress
        )
        t_train = time.time() - t0
        logger.info(f"Training done in {t_train:.1f}s, final loss={history['total_loss'][-1]:.4f}")

        # 3. Evaluate against previous generation
        logger.info(f"Evaluating: {args.eval_games} games vs previous gen...")
        old_model = ModelWrapper(device=str(model.device), num_filters=args.filters, num_res_blocks=args.blocks)
        if weight_files:
            old_model.load(os.path.join(WEIGHTS_DIR, weight_files[-1]))

        wins_new, wins_old, draws = _evaluate(model, old_model, args.eval_games, args.simulations // 2)
        total_games = wins_new + wins_old + draws
        win_rate = wins_new / max(total_games, 1)
        logger.info(f"Evaluation: new={wins_new} old={wins_old} draw={draws} (win_rate={win_rate:.1%})")

        # 4. Accept or reject
        if win_rate > 0.55 or not weight_files:
            gen_num = gen + 1
            path = os.path.join(WEIGHTS_DIR, f'gen_{gen_num:03d}.pt')
            model.save(path)
            weight_files.append(f'gen_{gen_num:03d}.pt')
            logger.info(f"ACCEPTED: saved as gen_{gen_num:03d}.pt")
        else:
            # Reload old weights
            model.load(os.path.join(WEIGHTS_DIR, weight_files[-1]))
            logger.info(f"REJECTED: reverting to {weight_files[-1]}")

    logger.info("\nTraining complete!")
    logger.info(f"Total generations: {len(weight_files)}")
    logger.info(f"Latest weights: {weight_files[-1] if weight_files else 'none'}")


def _evaluate(new_model, old_model, num_games, simulations):
    """Play games between new and old model. Returns (new_wins, old_wins, draws)."""
    from ai.game_logic import GameLogic, BLACK, WHITE, EMPTY
    from ai.mcts_engine import MCTSEngine

    mcts_new = MCTSEngine(simulations=simulations, nn_model=new_model)
    mcts_old = MCTSEngine(simulations=simulations, nn_model=old_model)

    wins_new = 0
    wins_old = 0
    draws = 0

    for i in range(num_games):
        # Alternate colors
        if i % 2 == 0:
            black_mcts, white_mcts = mcts_new, mcts_old
            new_color = BLACK
        else:
            black_mcts, white_mcts = mcts_old, mcts_new
            new_color = WHITE

        game = GameLogic()
        while not game.game_over:
            if game.current_player == BLACK:
                r, c = black_mcts.choose_move(game)
            else:
                r, c = white_mcts.choose_move(game)
            if not game.place_stone(r, c):
                break

        if game.winner == EMPTY:
            draws += 1
        elif game.winner == new_color:
            wins_new += 1
        else:
            wins_old += 1

    return wins_new, wins_old, draws


def main():
    parser = argparse.ArgumentParser(description='Gomoku AI Training Pipeline')
    parser.add_argument('--generations', type=int, default=10, help='Number of generations')
    parser.add_argument('--games', type=int, default=100, help='Self-play games per generation')
    parser.add_argument('--simulations', type=int, default=200, help='MCTS simulations per move')
    parser.add_argument('--epochs', type=int, default=10, help='Training epochs')
    parser.add_argument('--batch-size', type=int, default=64, help='Training batch size')
    parser.add_argument('--eval-games', type=int, default=20, help='Evaluation games')
    parser.add_argument('--lr', type=float, default=0.001, help='Learning rate')
    parser.add_argument('--filters', type=int, default=8, help='CNN filters (8=tiny, 64=full)')
    parser.add_argument('--blocks', type=int, default=1, help='ResBlocks (1=tiny, 3=full)')
    args = parser.parse_args()

    logger.info("Gomoku AI Training Pipeline")
    logger.info(f"Config: {vars(args)}")

    train(args)


if __name__ == '__main__':
    main()
