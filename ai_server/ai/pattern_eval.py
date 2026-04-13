"""Pattern evaluator - Python mirror of Godot pattern_evaluator.gd.

Fast NumPy/Python implementation used by pattern-guided MCTS and
for generating pattern feature planes for the CNN.
"""

import numpy as np
from ai.game_logic import BOARD_SIZE, EMPTY, BLACK, WHITE

DIRECTIONS = [(0, 1), (1, 0), (1, 1), (1, -1)]

# Default weights (matches GDScript)
DEFAULT_WEIGHTS = {
    "five": 100000.0,
    "open_four": 10000.0,
    "half_four": 1000.0,
    "open_three": 1000.0,
    "half_three": 100.0,
    "open_two": 100.0,
    "half_two": 10.0,
}

# v2 change: slight offense bias. DEFENSE_WEIGHT used to be 1.1 which
# produced endless-draw stalemates (both sides always block, never attack).
# 0.8 lets the attacker break through shared threats.
DEFENSE_WEIGHT = 0.8

# Multiplicative bonus when a single move creates 2+ strong patterns
# (double-three, double-four, four-three). These are tactically winning
# in real Gomoku, but a plain sum of per-direction scores doesn't rank
# them highly enough relative to a single strong pattern.
DOUBLE_THREAT_BONUS = 3.0
STRONG_PATTERN_THRESHOLD = 900.0  # open_three or better counts as "strong"


def _count_consecutive(board, row, col, dr, dc, player):
    """Returns (count, is_open_end)."""
    count = 0
    r, c = row + dr, col + dc
    while 0 <= r < BOARD_SIZE and 0 <= c < BOARD_SIZE and board[r][c] == player:
        count += 1
        r += dr
        c += dc
    is_open = 0
    if 0 <= r < BOARD_SIZE and 0 <= c < BOARD_SIZE and board[r][c] == EMPTY:
        is_open = 1
    return count, is_open


def _pattern_score(count, open_ends, weights=DEFAULT_WEIGHTS):
    if count >= 5:
        return weights["five"]
    if open_ends == 0:
        return 0.0
    if count == 4:
        return weights["open_four"] if open_ends == 2 else weights["half_four"]
    if count == 3:
        return weights["open_three"] if open_ends == 2 else weights["half_three"]
    if count == 2:
        return weights["open_two"] if open_ends == 2 else weights["half_two"]
    if count == 1:
        return 1.0
    return 0.0


def evaluate_position(board, row, col, player, weights=DEFAULT_WEIGHTS):
    """What patterns would placing 'player' at (row, col) create?

    Sums per-direction pattern scores with a multiplicative bonus when
    multiple directions are strong (captures double-three / double-four
    tactical wins). Returns a single float.
    """
    per_dir = []
    for dr, dc in DIRECTIONS:
        count = 1  # the stone being placed
        open_ends = 0
        pos_c, pos_o = _count_consecutive(board, row, col, dr, dc, player)
        count += pos_c
        open_ends += pos_o
        neg_c, neg_o = _count_consecutive(board, row, col, -dr, -dc, player)
        count += neg_c
        open_ends += neg_o
        per_dir.append(_pattern_score(count, open_ends, weights))

    total = sum(per_dir)
    # Double-threat bonus: if the move creates 2+ strong patterns
    # (open_three or better) across directions, it's tactically winning.
    strong_count = sum(1 for s in per_dir if s >= STRONG_PATTERN_THRESHOLD)
    if strong_count >= 2:
        total *= DOUBLE_THREAT_BONUS
    return total


def score_cell(board, row, col, player, weights=DEFAULT_WEIGHTS):
    """Score empty cell for player: offense + defense.

    Special case: if the opponent would make an open_four or five by
    playing here (i.e. we MUST block), the defense term dominates and
    we return it directly so MCTS priors are clearly peaked on the
    single forced-block move.
    """
    if board[row][col] != EMPTY:
        return 0.0
    opponent = WHITE if player == BLACK else BLACK
    attack = evaluate_position(board, row, col, player, weights)
    defend = evaluate_position(board, row, col, opponent, weights)

    # Forced-block case: opponent's move here would make an open_four
    # (10000) or five (100000). These are absolute priorities — any
    # attack we could build is worthless if we lose next move.
    if defend >= weights["open_four"]:
        return defend * 2.0 + attack  # strongly peaked

    # Forced-win case: our move here makes an open_four or five.
    if attack >= weights["open_four"]:
        return attack * 2.0 + defend

    return attack + defend * DEFENSE_WEIGHT


def detect_threats(board, row, col, player):
    """Return dict of bools: which pattern types would be created
    by placing 'player' at (row, col). Used for pattern feature planes.
    """
    if board[row][col] != EMPTY:
        return None

    result = {
        "five": False,
        "open_four": False,
        "half_four": False,
        "open_three": False,
        "half_three": False,
    }
    for dr, dc in DIRECTIONS:
        count = 1
        open_ends = 0
        pos_c, pos_o = _count_consecutive(board, row, col, dr, dc, player)
        count += pos_c
        open_ends += pos_o
        neg_c, neg_o = _count_consecutive(board, row, col, -dr, -dc, player)
        count += neg_c
        open_ends += neg_o

        if count >= 5:
            result["five"] = True
        elif count == 4:
            if open_ends == 2:
                result["open_four"] = True
            elif open_ends == 1:
                result["half_four"] = True
        elif count == 3:
            if open_ends == 2:
                result["open_three"] = True
            elif open_ends == 1:
                result["half_three"] = True
    return result


def make_feature_planes(board, current_player):
    """Generate 6 pattern feature planes.

    Returns float32 array of shape (6, 15, 15):
      0: self can make five (win)
      1: self can make open_four
      2: self can make open_three
      3: opponent can make five (must block)
      4: opponent can make open_four (must block)
      5: opponent can make open_three (should block)
    """
    opponent = WHITE if current_player == BLACK else BLACK
    planes = np.zeros((6, BOARD_SIZE, BOARD_SIZE), dtype=np.float32)

    for r in range(BOARD_SIZE):
        for c in range(BOARD_SIZE):
            if board[r][c] != EMPTY:
                continue
            self_t = detect_threats(board, r, c, current_player)
            opp_t = detect_threats(board, r, c, opponent)
            if self_t["five"]:
                planes[0, r, c] = 1.0
            if self_t["open_four"]:
                planes[1, r, c] = 1.0
            if self_t["open_three"]:
                planes[2, r, c] = 1.0
            if opp_t["five"]:
                planes[3, r, c] = 1.0
            if opp_t["open_four"]:
                planes[4, r, c] = 1.0
            if opp_t["open_three"]:
                planes[5, r, c] = 1.0
    return planes


def best_moves_by_score(board, candidates, player, top_k=None, weights=DEFAULT_WEIGHTS):
    """Sort candidates by score_cell descending. Return (move, score) list."""
    scored = []
    for r, c in candidates:
        s = score_cell(board, r, c, player, weights)
        scored.append(((r, c), s))
    scored.sort(key=lambda x: -x[1])
    if top_k is not None:
        scored = scored[:top_k]
    return scored
