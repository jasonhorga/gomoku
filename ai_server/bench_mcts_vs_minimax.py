"""Cross-check: does pattern-MCTS @ 1500 sims beat minimax-d4?

The iOS plugin's L5 (1500-sim pattern-MCTS) reportedly lost 0-20 to L4
(minimax d=4) in AI Lab. If the same thing happens in the Python
reference implementation, the algorithm itself is the problem. If
Python pattern-MCTS wins, then the Swift port has introduced a
regression.

Implements a minimax with:
- Depth 4 + alpha-beta
- Pattern-score leaf eval (sum over candidate cells)
- Top-20 candidate pruning per node (matches ai_minimax.gd)
- Immediate-win / must-block shortcuts
"""
import argparse
import sys
import time

from ai.game_logic import GameLogic, BLACK, WHITE, EMPTY
from ai.mcts_engine import MCTSEngine
from ai.pattern_eval import score_cell


class MinimaxEngine:
    """Port of scripts/ai/ai_minimax.gd for Python-side A/B testing."""

    def __init__(self, depth=4):
        self.depth = depth

    def choose_move(self, game: GameLogic):
        board = [row[:] for row in game.board]
        player = game.current_player
        opponent = WHITE if player == BLACK else BLACK

        candidates = self._get_sorted_candidates(board, player)
        if not candidates:
            return (7, 7)

        # Immediate win check
        for r, c in candidates:
            board[r][c] = player
            if self._check_win(board, r, c, player):
                board[r][c] = EMPTY
                return (r, c)
            board[r][c] = EMPTY

        # Full minimax search
        best_score = -float('inf')
        best_move = candidates[0]
        alpha, beta = -float('inf'), float('inf')
        for r, c in candidates[:20]:
            board[r][c] = player
            score = self._minimax(board, self.depth - 1, opponent, alpha, beta, False)
            board[r][c] = EMPTY
            if score > best_score:
                best_score = score
                best_move = (r, c)
            alpha = max(alpha, best_score)
        return best_move

    def _minimax(self, board, depth, current, alpha, beta, maximizing):
        if depth == 0:
            return self._evaluate_board(board)

        candidates = self._get_sorted_candidates(board, current)
        if not candidates:
            return self._evaluate_board(board)

        opponent = WHITE if current == BLACK else BLACK
        cands = candidates[:12]

        if maximizing:
            v = -float('inf')
            for r, c in cands:
                board[r][c] = current
                if self._check_win(board, r, c, current):
                    board[r][c] = EMPTY
                    return 100000
                s = self._minimax(board, depth - 1, opponent, alpha, beta, False)
                board[r][c] = EMPTY
                v = max(v, s)
                alpha = max(alpha, v)
                if beta <= alpha:
                    break
            return v
        else:
            v = float('inf')
            for r, c in cands:
                board[r][c] = current
                if self._check_win(board, r, c, current):
                    board[r][c] = EMPTY
                    return -100000
                s = self._minimax(board, depth - 1, opponent, alpha, beta, True)
                board[r][c] = EMPTY
                v = min(v, s)
                beta = min(beta, v)
                if beta <= alpha:
                    break
            return v

    def _evaluate_board(self, board):
        # Sum score_cell for both players, attack - defend.
        # Not identical to GDScript evaluate_board but directionally
        # similar: rewards positions where the side-to-play has more
        # threat surface than the opponent.
        my_total = 0.0
        opp_total = 0.0
        for r in range(15):
            for c in range(15):
                if board[r][c] == EMPTY:
                    continue
                my = board[r][c]
                opp = WHITE if my == BLACK else BLACK
                # Contribution from this stone's local pattern
                my_total += self._local_contribution(board, r, c, my)
                opp_total += self._local_contribution(board, r, c, opp)
        return my_total - opp_total

    def _local_contribution(self, board, r, c, player):
        # Score if I played each empty neighbor — proxy for threat level.
        total = 0.0
        for dr in (-1, 0, 1):
            for dc in (-1, 0, 1):
                nr, nc = r + dr, c + dc
                if 0 <= nr < 15 and 0 <= nc < 15 and board[nr][nc] == EMPTY:
                    total += score_cell(board, nr, nc, player)
        return total

    def _get_sorted_candidates(self, board, player):
        # Empty cells within radius 2 of any stone, sorted by pattern score
        candidates = set()
        any_stone = False
        for r in range(15):
            for c in range(15):
                if board[r][c] == EMPTY:
                    continue
                any_stone = True
                for dr in range(-2, 3):
                    for dc in range(-2, 3):
                        nr, nc = r + dr, c + dc
                        if 0 <= nr < 15 and 0 <= nc < 15 and board[nr][nc] == EMPTY:
                            candidates.add((nr, nc))
        if not any_stone:
            return [(7, 7)]
        scored = [((r, c), score_cell(board, r, c, player)) for r, c in candidates]
        scored.sort(key=lambda x: -x[1])
        return [m for m, _ in scored]

    def _check_win(self, board, row, col, p):
        for dr, dc in [(0, 1), (1, 0), (1, 1), (1, -1)]:
            count = 1
            for sign in (1, -1):
                r, c = row + dr * sign, col + dc * sign
                while 0 <= r < 15 and 0 <= c < 15 and board[r][c] == p:
                    count += 1
                    r += dr * sign
                    c += dc * sign
            if count >= 5:
                return True
        return False


def play_game(black_engine, white_engine, max_moves=225):
    game = GameLogic()
    move_idx = 0
    while not game.game_over and move_idx < max_moves:
        engine = black_engine if game.current_player == BLACK else white_engine
        r, c = engine.choose_move(game)
        if not game.place_stone(r, c):
            return 2 if game.current_player == BLACK else 1
        move_idx += 1
    return int(game.winner)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--games", type=int, default=10)
    p.add_argument("--sims", type=int, default=1500)
    p.add_argument("--depth", type=int, default=4)
    args = p.parse_args()

    mcts = MCTSEngine(simulations=args.sims, nn_model=None,
                      use_pattern_prior=True, vcf_depth=10,
                      dirichlet_alpha=0.0)
    minimax = MinimaxEngine(depth=args.depth)

    mcts_score = 0.0
    minimax_score = 0.0
    draws = 0
    t0 = time.time()

    for i in range(args.games):
        # Alternate colours so neither side gets a deterministic advantage.
        if i % 2 == 0:
            black, white = mcts, minimax
            b_label, w_label = "mcts", "minimax"
        else:
            black, white = minimax, mcts
            b_label, w_label = "minimax", "mcts"

        winner = play_game(black, white)
        if winner == BLACK:
            if b_label == "mcts":
                mcts_score += 1
            else:
                minimax_score += 1
        elif winner == WHITE:
            if w_label == "mcts":
                mcts_score += 1
            else:
                minimax_score += 1
        else:
            draws += 1
            mcts_score += 0.5
            minimax_score += 0.5

        done = i + 1
        result_char = 'B' if winner == BLACK else ('W' if winner != 0 else 'D')
        print(f"[{done}/{args.games}] {b_label}({result_char}) vs {w_label}"
              f" | mcts={mcts_score:.1f} minimax={minimax_score:.1f} draws={draws}",
              flush=True)

    dt = time.time() - t0
    print(f"\n== {args.games} games in {dt:.0f}s (mcts sims={args.sims}, minimax depth={args.depth}) ==")
    print(f"mcts    : {mcts_score:.1f} / {args.games} ({100 * mcts_score / args.games:.1f}%)")
    print(f"minimax : {minimax_score:.1f} / {args.games} ({100 * minimax_score / args.games:.1f}%)")
    print(f"draws   : {draws}")


if __name__ == "__main__":
    sys.exit(main())
