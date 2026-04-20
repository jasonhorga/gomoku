"""VCF (Victory by Continuous Four) search for Gomoku.

The key technique that lifts pattern-based play from "Level 5" to actually
winning games. Pattern MCTS alone gets stuck in mutual-defense stalemates
because neither side ever creates an unstoppable attack. VCF finds forced
win sequences by exploring only moves that create a four-threat (which
opponent MUST block), so the search tree is narrow and deep.

Algorithm:
  1. Try every move that creates a four (half_four / open_four / five).
  2. If it's a five → won.
  3. If it's an open_four → won next move (opponent can only block 1 side).
  4. Otherwise (half_four), find the single cell opponent MUST play to
     block the five-threat, place opponent there, and recurse.
  5. If recursion finds a win, we have a VCF line.

Branching factor is typically 1-4 (few positions create fours), so depth-8
search is fast (~ms).
"""

from ai.game_logic import BOARD_SIZE, EMPTY, BLACK, WHITE, DIRECTIONS
from ai.pattern_eval import _count_consecutive, _scan_line


def _makes_five(board, r, c, player):
    """Does placing player at (r, c) make 5 in a row?"""
    for dr, dc in DIRECTIONS:
        pos_c, _ = _count_consecutive(board, r, c, dr, dc, player)
        neg_c, _ = _count_consecutive(board, r, c, -dr, -dc, player)
        if 1 + pos_c + neg_c >= 5:
            return True
    return False


def _four_info(board, r, c, player):
    """After placing player at (r,c), return info about four-threats created.

    Detects both consecutive AND gapped patterns:
      - Consecutive four: XXXX with open end(s)
      - Gapped five: XXX_X or XX_XX etc. (5 stones with 1 gap → must block gap)

    Returns (kind, block_cells) where:
      kind: 'five' | 'open_four' | 'half_four' | None
      block_cells: cells opponent must play to prevent five
    """
    best_kind = None
    block_cells = []
    for dr, dc in DIRECTIONS:
        pos_con, pos_gap, pos_open, pos_gap_cell = _scan_line(
            board, r, c, dr, dc, player)
        neg_con, neg_gap, neg_open, neg_gap_cell = _scan_line(
            board, r, c, -dr, -dc, player)

        # --- Consecutive patterns (original logic) ---
        total = 1 + pos_con + neg_con
        open_ends = pos_open + neg_open
        if total >= 5:
            return 'five', []
        if total == 4:
            ends = []
            if pos_open:
                ends.append((r + (pos_con + 1) * dr, c + (pos_con + 1) * dc))
            if neg_open:
                ends.append((r - (neg_con + 1) * dr, c - (neg_con + 1) * dc))
            if open_ends == 2:
                if best_kind != 'five':
                    best_kind = 'open_four'
                block_cells.extend(ends)
            elif open_ends == 1:
                if best_kind not in ('five', 'open_four'):
                    best_kind = 'half_four'
                block_cells.extend(ends)

        # --- Gapped patterns (split-four detection) ---
        # 4+ stones across one gap → filling gap makes five → must block.
        # This is equivalent to a half_four with the gap as the block cell.
        if pos_gap > 0 and pos_gap_cell is not None:
            gap_total = 1 + pos_con + neg_con + pos_gap
            if gap_total >= 4:
                if best_kind not in ('five', 'open_four'):
                    best_kind = 'half_four'
                block_cells.append(pos_gap_cell)
        if neg_gap > 0 and neg_gap_cell is not None:
            gap_total = 1 + pos_con + neg_con + neg_gap
            if gap_total >= 4:
                if best_kind not in ('five', 'open_four'):
                    best_kind = 'half_four'
                block_cells.append(neg_gap_cell)

    return best_kind, block_cells


def _candidate_moves(board, radius=1):
    """Nearby empty cells (within radius of any stone).

    Returns a sorted list (by row, col) so iteration order is deterministic
    — the Swift port depends on this for bit-exact diff testing, and
    reproducible self-play games benefit too.
    """
    cands = set()
    has_stone = False
    for r in range(BOARD_SIZE):
        for c in range(BOARD_SIZE):
            if board[r][c] != EMPTY:
                has_stone = True
                for dr in range(-radius, radius + 1):
                    for dc in range(-radius, radius + 1):
                        nr, nc = r + dr, c + dc
                        if 0 <= nr < BOARD_SIZE and 0 <= nc < BOARD_SIZE:
                            if board[nr][nc] == EMPTY:
                                cands.add((nr, nc))
    if not has_stone:
        return [(BOARD_SIZE // 2, BOARD_SIZE // 2)]
    return sorted(cands)


def find_vcf(board, attacker, max_depth=10, max_branch=8):
    """Search for a forced-win move sequence via continuous fours.

    Returns the first winning move (r, c) or None if no VCF found.
    board is mutated during search but restored before return.

    Defaults (depth=10, branch=8) are the "max effort" settings. For
    real-time play, callers can pass smaller values to limit time.
    """
    return _vcf_recurse(board, attacker, max_depth, max_branch)


def _vcf_recurse(board, attacker, depth, max_branch):
    if depth <= 0:
        return None
    defender = WHITE if attacker == BLACK else BLACK

    # Immediate win check
    for r, c in _candidate_moves(board, radius=1):
        if _makes_five(board, r, c, attacker):
            return (r, c)

    # Gather four-threat moves
    four_moves = []
    for r, c in _candidate_moves(board, radius=2):
        board[r][c] = attacker
        kind, blocks = _four_info(board, r, c, attacker)
        board[r][c] = EMPTY
        if kind in ('open_four', 'half_four'):
            # open_four is instantly winning (unless defender also wins)
            priority = 2 if kind == 'open_four' else 1
            four_moves.append((priority, r, c, kind, blocks))

    # Try most promising first
    four_moves.sort(key=lambda x: -x[0])
    four_moves = four_moves[:max_branch]

    for _, r, c, kind, blocks in four_moves:
        board[r][c] = attacker

        # Counter-threat check: can the defender win IMMEDIATELY (five in
        # one move)? If so, skip this move.
        # Note: we don't check for defender's open_four counter here because
        # doing so at every recursive node is O(candidates²) and makes VCF
        # unusably slow. The attacker's half_four is a force-win in 2, and
        # defender's open_four counter is also a force-win in 2 — the race
        # is symmetric, so we commit to our VCF and let the outer MCTS
        # tiebreak if needed.
        defender_wins = False
        for dr, dc in _candidate_moves(board, radius=1):
            if _makes_five(board, dr, dc, defender):
                defender_wins = True
                break

        if defender_wins:
            board[r][c] = EMPTY
            continue

        if kind == 'open_four':
            # Opponent can only block one end; we win next move
            board[r][c] = EMPTY
            return (r, c)

        # half_four: opponent must block the single open end
        # (there might be multiple equivalent blocks if 2+ directions made fours)
        if not blocks:
            board[r][c] = EMPTY
            continue

        # Try each forced block; if ALL lead to recursive VCF wins, we've won.
        # sorted() for deterministic iteration (matches Swift port).
        all_blocked = True
        for br, bc in sorted(set(blocks)):
            if board[br][bc] != EMPTY:
                continue
            board[br][bc] = defender

            # Does defender's block create their own 4-threat we must answer?
            # For simplicity, ignore counter-threats and just recurse.
            sub = _vcf_recurse(board, attacker, depth - 1, max_branch)

            board[br][bc] = EMPTY
            if sub is None:
                all_blocked = False
                break

        board[r][c] = EMPTY
        if all_blocked:
            return (r, c)

    return None
