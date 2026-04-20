"""VCT (Victory by Continuous Threats) search for Gomoku.

Extends VCF by also considering three-threats (moves that create open
threes). Where VCF only searches sequences of fours (branching ~1),
VCT searches mixed four+three sequences (branching ~2-3).

Key win conditions VCT catches that VCF misses:
  - Double-three: a single move creates 2+ open threes → unstoppable
  - Four-three: a move creates a four + an open three → unstoppable
  - Three-sequence: repeated three-threats that eventually reach a VCF

Algorithm:
  1. Check VCF first (faster, always higher priority).
  2. Try moves that create open threes (3 consecutive, both ends open).
  3. If a move creates double-three or four+three → instant win.
  4. Otherwise, enumerate defender's responses (the two extension cells
     where the three could become a four).
  5. For EACH defense, recursively check if attacker still has VCT.
  6. If ALL defenses lead to attacker win → this is a VCT winning move.

Limitation: only detects consecutive patterns. Gapped patterns (like
X X X _ X split-fours) require separate handling.
"""

from ai.game_logic import BOARD_SIZE, EMPTY, BLACK, WHITE, DIRECTIONS
from ai.pattern_eval import _count_consecutive
from ai.vcf_search import find_vcf, _four_info, _makes_five, _candidate_moves


def find_vct(board, attacker, max_depth=6, max_branch=6):
    """Search for a forced win via continuous threats (fours + threes).

    Returns the first winning move (r, c) or None.
    Board is mutated during search but restored before return.
    """
    # VCF is always tried first — faster and catches pure-four sequences
    vcf = find_vcf(board, attacker, max_depth=max_depth)
    if vcf is not None:
        return vcf
    return _vct_recurse(board, attacker, max_depth, max_branch)


def _get_open_threes(board, r, c, player):
    """After placing player at (r,c), return open threes created.

    Returns list of ((dr,dc), [ext_cell_1, ext_cell_2]) for each
    direction that forms an open three (3 consecutive, both ends open).
    Extension cells are where the attacker would play next to make a four.
    """
    result = []
    for dr, dc in DIRECTIONS:
        pos_c, pos_o = _count_consecutive(board, r, c, dr, dc, player)
        neg_c, neg_o = _count_consecutive(board, r, c, -dr, -dc, player)
        total = 1 + pos_c + neg_c
        open_ends = pos_o + neg_o
        if total == 3 and open_ends == 2:
            ext = []
            if pos_o:
                ext.append((r + (pos_c + 1) * dr, c + (pos_c + 1) * dc))
            if neg_o:
                ext.append((r - (neg_c + 1) * dr, c - (neg_c + 1) * dc))
            result.append(((dr, dc), ext))
    return result


def _defender_has_five(board, defender):
    """Can defender win immediately by placing one stone?"""
    for r, c in _candidate_moves(board, radius=1):
        if board[r][c] == EMPTY and _makes_five(board, r, c, defender):
            return True
    return False


def _vct_recurse(board, attacker, depth, max_branch):
    if depth <= 0:
        return None

    defender = WHITE if attacker == BLACK else BLACK

    # VCF check at every level — fours always dominate threes
    vcf = find_vcf(board, attacker, max_depth=depth)
    if vcf is not None:
        return vcf

    # Find moves that create open threes
    threat_moves = []
    for r, c in _candidate_moves(board, radius=2):
        if board[r][c] != EMPTY:
            continue
        board[r][c] = attacker
        threes = _get_open_threes(board, r, c, attacker)
        kind, _ = _four_info(board, r, c, attacker)
        board[r][c] = EMPTY

        if not threes:
            continue

        # Priority: double-three > four+three > single three
        has_four = kind in ('open_four', 'half_four')
        n_threes = len(threes)
        priority = n_threes * 10 + (5 if has_four else 0)
        threat_moves.append((priority, r, c, threes, has_four))

    threat_moves.sort(key=lambda x: -x[0])
    threat_moves = threat_moves[:max_branch]

    for _, r, c, threes, has_four in threat_moves:
        board[r][c] = attacker

        # Counter-check: can defender win immediately (five)?
        if _defender_has_five(board, defender):
            board[r][c] = EMPTY
            continue

        # Double-three or four+three: instant win
        # (defender can block at most one threat per turn)
        if len(threes) >= 2 or (has_four and len(threes) >= 1):
            board[r][c] = EMPTY
            return (r, c)

        # Single open three: enumerate defense moves
        # Defense = the extension cells of the open three
        # (if defender doesn't block one, attacker extends to open four → win)
        defense_cells = set()
        for (dr, dc), ext_cells in threes:
            for cell in ext_cells:
                if (0 <= cell[0] < BOARD_SIZE and 0 <= cell[1] < BOARD_SIZE
                        and board[cell[0]][cell[1]] == EMPTY):
                    defense_cells.add(cell)

        if not defense_cells:
            board[r][c] = EMPTY
            continue

        # For ALL defense moves, can attacker still win?
        # sorted() for deterministic iteration (matches Swift port).
        all_win = True
        for def_r, def_c in sorted(defense_cells):
            board[def_r][def_c] = defender
            sub = _vct_recurse(board, attacker, depth - 1, max_branch)
            board[def_r][def_c] = EMPTY
            if sub is None:
                all_win = False
                break

        board[r][c] = EMPTY
        if all_win:
            return (r, c)

    return None
