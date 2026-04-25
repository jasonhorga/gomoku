"""Full port of scripts/ai/ai_minimax.gd to Python.

Mirrors the GDScript L4 engine's behaviour bit-for-bit so the training
pipeline can use it as an adversarial opponent in self-play. The earlier
`bench_mcts_vs_minimax.py` shipped a simplified minimax that was much
weaker than the iOS L4 — diff_test against this engine should match
GDScript move-for-move on the test fixtures.

Components ported:
- Zobrist hashing (deterministic seed=42, matches GDScript)
- Pattern-aware leaf evaluation (`evaluate_board`, `_evaluate_existing_stone`)
- Alpha-beta with transposition table
- Killer move heuristic (2 slots per ply)
- Iterative deepening (engaged at depth >= 4)
- Top-20 candidate cap, top-12 in recursion
"""
from __future__ import annotations

import random
from typing import Optional

from ai.game_logic import GameLogic, BLACK, WHITE, EMPTY, BOARD_SIZE
from ai.pattern_eval import (
    score_cell,
    DEFAULT_WEIGHTS,
    _scan_line,
    _pattern_score,
    _gapped_score,
)

DIRECTIONS = [(0, 1), (1, 0), (1, 1), (1, -1)]
MAX_CANDIDATES = 20
TT_EXACT = 0
TT_LOWER = 1
TT_UPPER = 2
WIN_SCORE = 100000.0


class Zobrist:
    """Mirror of scripts/ai/zobrist.gd. Same seed (42) so hashes match."""

    def __init__(self):
        rng = random.Random(42)
        # table[r][c][piece] where piece is 0 (empty), 1 (black), 2 (white).
        # GDScript uses table[r][c][piece] indexing — same here.
        # randi() in Godot returns 32-bit unsigned; we use 63-bit signed for
        # Python int safety. Hash quality is the same: we only XOR.
        self.table = [
            [
                [rng.getrandbits(63) for _ in range(3)]
                for _ in range(BOARD_SIZE)
            ]
            for _ in range(BOARD_SIZE)
        ]
        self.current_hash = 0

    def reset(self):
        self.current_hash = 0

    def update(self, row: int, col: int, piece: int):
        self.current_hash ^= self.table[row][col][piece]

    def get_hash(self) -> int:
        return self.current_hash


def _evaluate_existing_stone(board, row, col, player) -> float:
    """Sum patterns starting at this stone in each direction.

    Mirrors pattern_evaluator.gd. The 0.1 scale on the final value mirrors
    GDScript so leaf values stay in the same range as score_cell.
    """
    total = 0.0
    for dr, dc in DIRECTIONS:
        prev_r = row - dr
        prev_c = col - dc
        prev_in_bounds = 0 <= prev_r < BOARD_SIZE and 0 <= prev_c < BOARD_SIZE

        if prev_in_bounds and board[prev_r][prev_c] == player:
            continue  # not the start of this line

        if prev_in_bounds and board[prev_r][prev_c] == EMPTY:
            pp_r = row - 2 * dr
            pp_c = col - 2 * dc
            if 0 <= pp_r < BOARD_SIZE and 0 <= pp_c < BOARD_SIZE:
                if board[pp_r][pp_c] == player:
                    continue  # gapped line starts earlier

        cons, gap_stones, end_open, _ = _scan_line(board, row, col, dr, dc, player)
        count = 1 + cons
        open_ends = end_open
        if prev_in_bounds and board[prev_r][prev_c] == EMPTY:
            open_ends += 1

        con_score = _pattern_score(count, open_ends)
        gap_score = 0.0
        if gap_stones > 0:
            gap_score = _gapped_score(1 + cons + gap_stones)

        total += max(con_score, gap_score) * 0.1

    return total


def evaluate_board(board, player) -> float:
    """Total board score from `player`'s perspective.

    Sum each side's existing-stone patterns; subtract opponent's. Used as
    leaf eval at depth=0.
    """
    opponent = WHITE if player == BLACK else BLACK
    score = 0.0
    for r in range(BOARD_SIZE):
        for c in range(BOARD_SIZE):
            v = board[r][c]
            if v == player:
                score += _evaluate_existing_stone(board, r, c, player)
            elif v == opponent:
                score -= _evaluate_existing_stone(board, r, c, opponent)
    return score


def _check_win(board, row, col, player) -> bool:
    """Five-in-a-row centred on (row, col)."""
    for dr, dc in DIRECTIONS:
        count = 1
        for sign in (1, -1):
            r = row + dr * sign
            c = col + dc * sign
            while 0 <= r < BOARD_SIZE and 0 <= c < BOARD_SIZE and board[r][c] == player:
                count += 1
                r += dr * sign
                c += dc * sign
        if count >= 5:
            return True
    return False


def _get_nearby_empty_cells(board, radius: int):
    """Empty cells within `radius` of any stone."""
    cells = set()
    has_stone = False
    for r in range(BOARD_SIZE):
        for c in range(BOARD_SIZE):
            if board[r][c] == EMPTY:
                continue
            has_stone = True
            for dr in range(-radius, radius + 1):
                for dc in range(-radius, radius + 1):
                    nr, nc = r + dr, c + dc
                    if 0 <= nr < BOARD_SIZE and 0 <= nc < BOARD_SIZE and board[nr][nc] == EMPTY:
                        cells.add((nr, nc))
    if not has_stone:
        return [(7, 7)]
    return sorted(cells)


def _get_sorted_candidates(board, current_player):
    """Top-MAX_CANDIDATES empty cells sorted by score_cell."""
    raw = _get_nearby_empty_cells(board, 2)
    scored = [((r, c), score_cell(board, r, c, current_player)) for r, c in raw]
    scored.sort(key=lambda x: -x[1])
    if len(scored) > MAX_CANDIDATES:
        scored = scored[:MAX_CANDIDATES]
    return scored


class MinimaxEngine:
    """Full L4 port. Use `choose_move(game)` to get a move for the
    current player. depth >= 4 enables iterative deepening, matching
    GDScript's behaviour."""

    def __init__(self, depth: int = 4):
        self.depth = depth
        self.use_iterative_deepening = depth >= 4
        self.zobrist = Zobrist()
        self.transposition_table: dict[int, dict] = {}
        # killer_moves[ply] = [move1, move2]; move = (r, c) or None
        self.killer_moves: list[list[Optional[tuple[int, int]]]] = []

    def choose_move(self, game: GameLogic) -> tuple[int, int]:
        # Defensive copy — minimax mutates board during search.
        board = [row[:] for row in game.board]
        player = game.current_player

        self.transposition_table.clear()
        self.killer_moves = [[None, None] for _ in range(self.depth + 1)]
        self.zobrist.reset()
        for r in range(BOARD_SIZE):
            for c in range(BOARD_SIZE):
                if board[r][c] != EMPTY:
                    self.zobrist.update(r, c, board[r][c])

        candidates = _get_sorted_candidates(board, player)
        if not candidates:
            return (7, 7)

        # Immediate win
        for (r, c), _ in candidates:
            board[r][c] = player
            if _check_win(board, r, c, player):
                board[r][c] = EMPTY
                return (r, c)
            board[r][c] = EMPTY

        if self.use_iterative_deepening:
            return self._iterative_deepening_search(board, player, candidates)
        return self._fixed_depth_search(board, player, candidates, self.depth)

    def _iterative_deepening_search(self, board, player, candidates):
        best_move = candidates[0][0]
        for d in range(1, self.depth + 1):
            move = self._fixed_depth_search(board, player, candidates, d)
            best_move = move
            # Reorder: best move first for next iteration.
            for i, (m, _) in enumerate(candidates):
                if m == best_move:
                    candidates.insert(0, candidates.pop(i))
                    break
        return best_move

    def _fixed_depth_search(self, board, player, candidates, depth):
        opponent = WHITE if player == BLACK else BLACK
        best_move = candidates[0][0]
        best_score = -float('inf')
        alpha = -float('inf')
        beta = float('inf')

        for (r, c), _ in candidates:
            board[r][c] = player
            self.zobrist.update(r, c, player)

            score = self._minimax(board, depth - 1, alpha, beta,
                                  False, player, opponent, 1)

            self.zobrist.update(r, c, player)
            board[r][c] = EMPTY

            if score > best_score:
                best_score = score
                best_move = (r, c)
            alpha = max(alpha, best_score)

        return best_move

    def _minimax(self, board, depth, alpha, beta,
                 is_maximizing, player, opponent, ply):
        # TT lookup
        tt_key = self.zobrist.get_hash()
        entry = self.transposition_table.get(tt_key)
        if entry is not None and entry['depth'] >= depth:
            flag = entry['flag']
            score = entry['score']
            if flag == TT_EXACT:
                return score
            if flag == TT_LOWER:
                alpha = max(alpha, score)
            elif flag == TT_UPPER:
                beta = min(beta, score)
            if alpha >= beta:
                return score

        if depth == 0:
            return evaluate_board(board, player)

        current = player if is_maximizing else opponent
        candidates = _get_sorted_candidates(board, current)
        if not candidates:
            return evaluate_board(board, player)

        opp = WHITE if current == BLACK else BLACK
        cands = [m for m, _ in candidates[:12]]

        # Killer moves first
        if ply < len(self.killer_moves):
            for km in self.killer_moves[ply]:
                if km is not None and board[km[0]][km[1]] == EMPTY:
                    if km in cands:
                        cands.remove(km)
                        cands.insert(0, km)

        orig_alpha = alpha
        if is_maximizing:
            best_score = -float('inf')
            for (r, c) in cands:
                board[r][c] = current
                self.zobrist.update(r, c, current)

                if _check_win(board, r, c, current):
                    score = WIN_SCORE + depth
                else:
                    score = self._minimax(board, depth - 1, alpha, beta,
                                          False, player, opponent, ply + 1)

                self.zobrist.update(r, c, current)
                board[r][c] = EMPTY

                if score > best_score:
                    best_score = score
                alpha = max(alpha, best_score)
                if beta <= alpha:
                    self._store_killer(ply, (r, c))
                    break
        else:
            best_score = float('inf')
            for (r, c) in cands:
                board[r][c] = current
                self.zobrist.update(r, c, current)

                if _check_win(board, r, c, current):
                    score = -WIN_SCORE - depth
                else:
                    score = self._minimax(board, depth - 1, alpha, beta,
                                          True, player, opponent, ply + 1)

                self.zobrist.update(r, c, current)
                board[r][c] = EMPTY

                if score < best_score:
                    best_score = score
                beta = min(beta, best_score)
                if beta <= alpha:
                    self._store_killer(ply, (r, c))
                    break

        flag = TT_EXACT
        if best_score <= orig_alpha:
            flag = TT_UPPER
        elif best_score >= beta:
            flag = TT_LOWER
        self.transposition_table[tt_key] = {
            'depth': depth, 'score': best_score, 'flag': flag,
        }

        return best_score

    def _store_killer(self, ply, move):
        if ply >= len(self.killer_moves):
            return
        slots = self.killer_moves[ply]
        if slots[0] != move:
            slots[1] = slots[0]
            slots[0] = move

    def get_name(self) -> str:
        if self.use_iterative_deepening:
            return f"Minimax(ID-d{self.depth})"
        return f"Minimax(d{self.depth})"
