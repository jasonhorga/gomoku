"""Self-play data generation using MCTS + neural network."""

import numpy as np
from ai.game_logic import GameLogic, BOARD_SIZE, BLACK, WHITE, EMPTY
from ai.mcts_engine import MCTSEngine


class SelfPlayWorker:
    def __init__(self, model_wrapper, simulations=400):
        self.model = model_wrapper
        self.mcts = MCTSEngine(simulations=simulations, nn_model=model_wrapper)

    def play_game(self) -> list:
        """
        Play one self-play game.
        Returns list of (state_tensor, mcts_probs, result_from_current_player_perspective)
        """
        game = GameLogic()
        history = []  # (tensor, probs, player)

        while not game.game_over:
            # Get MCTS move probabilities
            probs = self.mcts.get_move_probabilities(game)

            # Store training data
            tensor = game.to_tensor(game.current_player)
            history.append((tensor, probs, game.current_player))

            # Sample move from probabilities (with temperature)
            move_idx = self._sample_move(probs, len(game.move_history))
            row, col = move_idx // BOARD_SIZE, move_idx % BOARD_SIZE

            if not game.place_stone(row, col):
                # Fallback: pick highest prob valid move
                valid_moves = game.get_valid_moves()
                if not valid_moves:
                    break
                row, col = valid_moves[0]
                game.place_stone(row, col)

        # Assign result values
        training_data = []
        for tensor, probs, player in history:
            if game.winner == EMPTY:
                value = 0.0
            elif game.winner == player:
                value = 1.0
            else:
                value = -1.0
            training_data.append((tensor, probs, value))

        return training_data

    def _sample_move(self, probs: np.ndarray, move_count: int) -> int:
        """Sample a move from probabilities with temperature."""
        if move_count < 10:
            # Higher temperature early game for diversity
            temp = 1.0
        else:
            # Lower temperature later for stronger play
            temp = 0.3

        if temp < 0.01:
            return np.argmax(probs)

        probs_temp = probs ** (1.0 / temp)
        total = probs_temp.sum()
        if total <= 0:
            # Fallback: uniform random over non-zero
            nonzero = np.where(probs > 0)[0]
            if len(nonzero) == 0:
                return 0
            return np.random.choice(nonzero)

        probs_temp /= total
        return np.random.choice(len(probs_temp), p=probs_temp)


def run_self_play(model_wrapper, num_games: int, simulations: int = 400,
                  on_progress=None) -> list:
    """Run multiple self-play games and collect training data."""
    worker = SelfPlayWorker(model_wrapper, simulations)
    all_data = []

    for i in range(num_games):
        game_data = worker.play_game()
        all_data.extend(game_data)
        if on_progress:
            on_progress(i + 1, num_games, len(game_data))

    return all_data
