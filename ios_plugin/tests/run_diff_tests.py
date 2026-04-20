#!/usr/bin/env python3
"""Differential tester: Python ai/game_logic.py vs Swift GameLogic.swift.

Generates random board positions, runs each operation through both
implementations, fails on any mismatch. This is the per-advisor "test
each function before moving on" gate — catches bugs early instead of
letting them aggregate into MCTS-level mysteries.

Usage:
    python3 run_diff_tests.py [--cases N] [--seed S] [--cli PATH]
"""

import argparse
import json
import math
import os
import random
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
AI_SERVER = os.path.abspath(os.path.join(HERE, '..', '..', 'ai_server'))
sys.path.insert(0, AI_SERVER)

import numpy as np  # noqa: E402
from ai.game_logic import GameLogic, BOARD_SIZE, BLACK, WHITE  # noqa: E402
from ai import pattern_eval  # noqa: E402
from ai.vcf_search import (  # noqa: E402
    find_vcf, _candidate_moves, _makes_five, _four_info,
)
from ai.vct_search import find_vct, _get_open_threes  # noqa: E402
from ai.mcts_engine import MCTSEngine, _softmax_prior  # noqa: E402
from ai.pattern_eval import score_cell  # noqa: E402


def random_board(rng: random.Random, max_stones: int = 40):
    """Build a random mid-game board by legal play. Returns (2D list, current_player, history)."""
    game = GameLogic()
    n_target = rng.randint(0, max_stones)
    attempts = 0
    while len(game.move_history) < n_target and attempts < n_target * 5 + 10:
        attempts += 1
        if game.game_over:
            break
        r = rng.randint(0, BOARD_SIZE - 1)
        c = rng.randint(0, BOARD_SIZE - 1)
        game.place_stone(r, c)
    return game.board.tolist(), int(game.current_player), [list(m) for m in game.move_history]


def call_swift(cli: str, payload: dict) -> dict:
    proc = subprocess.run(
        [cli], input=json.dumps(payload).encode(),
        capture_output=True, timeout=10,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f"swift CLI exited {proc.returncode}; stderr=\n{proc.stderr.decode()}")
    return json.loads(proc.stdout)


class Diff:
    def __init__(self):
        self.checks = 0
        self.mismatches = []

    def expect(self, label: str, py, sw):
        self.checks += 1
        if py != sw:
            self.mismatches.append((label, py, sw))

    def expect_close(self, label: str, py, sw,
                     rel_tol: float = 1e-9, abs_tol: float = 1e-12):
        """Approx-equal float comparison. numpy.exp and libm's exp agree
        on the same x86/arm libm, but numpy's vectorised path occasionally
        differs from the scalar Foundation.exp by 1–2 ULPs, which then
        ripples through softmax/tanh. Values that depend on those ops
        should use this instead of exact equality."""
        self.checks += 1
        if py is None and sw is None:
            return
        if py is None or sw is None:
            self.mismatches.append((label, py, sw))
            return
        if not math.isclose(py, sw, rel_tol=rel_tol, abs_tol=abs_tol):
            self.mismatches.append((label, py, sw))

    def summary(self, total_cases: int) -> int:
        print(f"\n{self.checks} comparisons across {total_cases} random cases")
        if not self.mismatches:
            print("[PASS] Python and Swift implementations agree.")
            return 0
        print(f"[FAIL] {len(self.mismatches)} mismatches:")
        for label, py, sw in self.mismatches[:20]:
            print(f"  - {label}")
            print(f"      python: {py}")
            print(f"      swift:  {sw}")
        if len(self.mismatches) > 20:
            print(f"  ... and {len(self.mismatches) - 20} more")
        return 1


def test_case(rng: random.Random, cli: str, diff: Diff):
    board, player, history = random_board(rng)
    board_np = np.array(board, dtype=np.int8)

    # ---- GameLogic ops ----

    # 1. nearby_moves — output is a set equality check
    for radius in (1, 2):
        g = GameLogic()
        g.board = board_np.copy()
        g.current_player = player
        py_moves = sorted(tuple(m) for m in g.get_nearby_moves(radius))
        sw_resp = call_swift(cli, {
            "op": "nearby_moves", "board": board, "player": player, "radius": radius,
        })
        sw_moves = sorted(tuple(m) for m in sw_resp.get("moves", []))
        diff.expect(f"nearby_moves(r={radius})", py_moves, sw_moves)

    # 2. valid_moves — same check
    g = GameLogic()
    g.board = board_np.copy()
    py_valid = sorted(tuple(m) for m in g.get_valid_moves())
    sw_resp = call_swift(cli, {
        "op": "valid_moves", "board": board, "player": player,
    })
    sw_valid = sorted(tuple(m) for m in sw_resp.get("moves", []))
    diff.expect("valid_moves", py_valid, sw_valid)

    # 3. check_win — place a stone on a random empty cell, see if the
    #    win detection agrees
    empty_cells = [(r, c) for r in range(BOARD_SIZE) for c in range(BOARD_SIZE)
                    if board[r][c] == 0]
    if empty_cells:
        r, c = rng.choice(empty_cells)
        # Tentatively place stone and ask both sides
        board_with = [row[:] for row in board]
        board_with[r][c] = player
        g2 = GameLogic()
        g2.board = np.array(board_with, dtype=np.int8)
        py_win = bool(g2._check_win(r, c))
        sw_resp = call_swift(cli, {
            "op": "check_win", "board": board_with, "row": r, "col": c,
        })
        sw_win = bool(sw_resp.get("win", False))
        diff.expect(f"check_win({r},{c})", py_win, sw_win)

    # 4. count_direction — count consecutive `player` stones starting
    # one step past (r, c) in each cardinal + diagonal direction.
    # Use ORIGINAL board (no speculative stone); pick a random cell
    # and count for both players.
    g_cnt = GameLogic()
    g_cnt.board = board_np.copy()
    if empty_cells:
        r, c = rng.choice(empty_cells)
        for dr, dc in [(0, 1), (1, 0), (1, 1), (1, -1)]:
            for cnt_player in (BLACK, WHITE):
                py_count = g_cnt._count_dir(r, c, dr, dc, cnt_player)
                sw_resp = call_swift(cli, {
                    "op": "count_direction", "board": board,
                    "row": r, "col": c, "dr": dr, "dc": dc, "cnt_player": cnt_player,
                })
                sw_count = sw_resp.get("count", -1)
                diff.expect(
                    f"count_direction({r},{c},{dr},{dc},p={cnt_player})",
                    py_count, sw_count)

    # ---- PatternEval ops ----

    # Sample up to 5 empty cells for scoring tests.
    sample_cells = rng.sample(empty_cells, min(5, len(empty_cells))) if empty_cells else []

    # 5. score_cell — float, should be bit-exact (all ops are exact
    # doubles: integer weights times 0.8 yields deterministic IEEE754).
    for (r, c) in sample_cells:
        for eval_player in (BLACK, WHITE):
            py_score = float(pattern_eval.score_cell(board_np, r, c, eval_player))
            sw_resp = call_swift(cli, {
                "op": "score_cell", "board": board,
                "row": r, "col": c, "eval_player": eval_player,
            })
            sw_score = float(sw_resp.get("score", float('nan')))
            diff.expect(f"score_cell({r},{c},p={eval_player})", py_score, sw_score)

    # 6. evaluate_position — core of score_cell, test independently
    for (r, c) in sample_cells[:3]:
        for eval_player in (BLACK, WHITE):
            py_score = float(pattern_eval.evaluate_position(board_np, r, c, eval_player))
            sw_resp = call_swift(cli, {
                "op": "evaluate_position", "board": board,
                "row": r, "col": c, "eval_player": eval_player,
            })
            sw_score = float(sw_resp.get("score", float('nan')))
            diff.expect(f"evaluate_position({r},{c},p={eval_player})", py_score, sw_score)

    # 7. detect_threats — dict of bools, full equality.
    for (r, c) in sample_cells[:3]:
        for eval_player in (BLACK, WHITE):
            py_threats = pattern_eval.detect_threats(board_np, r, c, eval_player)
            sw_resp = call_swift(cli, {
                "op": "detect_threats", "board": board,
                "row": r, "col": c, "eval_player": eval_player,
            })
            sw_threats = sw_resp.get("threats")
            if py_threats is None:
                diff.expect(f"detect_threats({r},{c},p={eval_player}).null", None, sw_threats)
            else:
                # Compare the 5 keys we expose.
                for k in ("five", "open_four", "half_four", "open_three", "half_three"):
                    diff.expect(
                        f"detect_threats({r},{c},p={eval_player}).{k}",
                        bool(py_threats[k]), bool(sw_threats.get(k, None)))

    # 8. make_feature_planes — (6, 15, 15) float tensor, all 0/1.
    py_planes = pattern_eval.make_feature_planes(board_np, player)  # (6, 15, 15) float32
    py_flat = py_planes.flatten().tolist()
    sw_resp = call_swift(cli, {
        "op": "make_feature_planes", "board": board, "eval_player": player,
    })
    sw_flat = sw_resp.get("planes", [])
    diff.expect(
        f"make_feature_planes(p={player}).length",
        len(py_flat), len(sw_flat))
    if len(py_flat) == len(sw_flat):
        mismatches = sum(1 for a, b in zip(py_flat, sw_flat) if a != b)
        diff.expect(
            f"make_feature_planes(p={player}).mismatch_count",
            0, mismatches)

    # ---- VCF / VCT ops ----
    # find_vcf/vct mutate their board arg. Pass a deep copy and reset
    # current_player — both implementations use the 2D list form here.

    # 9. vcf_candidates — sorted nearby cells (VCF's own, not GameLogic's).
    for radius in (1, 2):
        py_cands = list(_candidate_moves([row[:] for row in board], radius=radius))
        sw_resp = call_swift(cli, {
            "op": "vcf_candidates", "board": board, "radius": radius,
        })
        sw_cands = [tuple(m) for m in sw_resp.get("moves", [])]
        diff.expect(f"vcf_candidates(r={radius})",
                    py_cands, sw_cands)

    # 10. makes_five on sample empty cells for both players.
    for (r, c) in sample_cells[:3]:
        for who in (BLACK, WHITE):
            py = bool(_makes_five([row[:] for row in board], r, c, who))
            sw_resp = call_swift(cli, {
                "op": "makes_five", "board": board,
                "row": r, "col": c, "player": who,
            })
            sw = bool(sw_resp.get("makes_five", False))
            diff.expect(f"makes_five({r},{c},p={who})", py, sw)

    # 11. four_info on sample cells (same cells, both players). Normalise
    # kind to string; blocks as a sorted dedup'd list so Python's
    # extend()-then-set() is comparable to Swift's explicit dedup.
    for (r, c) in sample_cells[:3]:
        for who in (BLACK, WHITE):
            b2 = [row[:] for row in board]
            b2[r][c] = who
            py_kind, py_blocks = _four_info(b2, r, c, who)
            py_blocks_norm = sorted(set(tuple(bc) for bc in py_blocks))
            sw_resp = call_swift(cli, {
                "op": "four_info", "board": b2,
                "row": r, "col": c, "player": who,
            })
            sw_kind = sw_resp.get("kind")
            sw_blocks = [tuple(bc) for bc in sw_resp.get("blocks", [])]
            diff.expect(f"four_info({r},{c},p={who}).kind",
                        py_kind, sw_kind)
            diff.expect(f"four_info({r},{c},p={who}).blocks",
                        py_blocks_norm, sw_blocks)

    # 12. open_threes — used by VCT. Normalise Python output to match
    # DiffTestCLI's encoding (direction-sorted, extensions sorted).
    for (r, c) in sample_cells[:3]:
        for who in (BLACK, WHITE):
            b2 = [row[:] for row in board]
            b2[r][c] = who
            py_threes = _get_open_threes(b2, r, c, who)
            py_norm = sorted(
                (tuple(d), sorted(tuple(e) for e in exts))
                for d, exts in py_threes
            )
            sw_resp = call_swift(cli, {
                "op": "open_threes", "board": b2,
                "row": r, "col": c, "player": who,
            })
            sw_threes = sw_resp.get("threes", [])
            sw_norm = [
                (tuple(t["dir"]), [tuple(e) for e in t["extensions"]])
                for t in sw_threes
            ]
            diff.expect(f"open_threes({r},{c},p={who})", py_norm, sw_norm)

    # 13. find_vcf — compare (r, c) tuple or None. With the determinism
    # patch (sorted candidate_moves + sorted blocks), Python and Swift
    # walk the same branches in the same order, so the first winning
    # move they return must be identical.
    # Use shallow depth/branch to keep per-case time <~1s.
    for attacker in (BLACK, WHITE):
        py = find_vcf([row[:] for row in board], attacker,
                       max_depth=6, max_branch=8)
        sw_resp = call_swift(cli, {
            "op": "find_vcf", "board": board, "attacker": attacker,
            "max_depth": 6, "max_branch": 8,
        })
        sw_raw = sw_resp.get("move")
        sw = tuple(sw_raw) if sw_raw is not None else None
        diff.expect(f"find_vcf(attacker={attacker})",
                    tuple(py) if py is not None else None, sw)

    # 14. find_vct — same idea, lower depth since branching is higher.
    for attacker in (BLACK, WHITE):
        py = find_vct([row[:] for row in board], attacker,
                       max_depth=4, max_branch=6)
        sw_resp = call_swift(cli, {
            "op": "find_vct", "board": board, "attacker": attacker,
            "max_depth": 4, "max_branch": 6,
        })
        sw_raw = sw_resp.get("move")
        sw = tuple(sw_raw) if sw_raw is not None else None
        diff.expect(f"find_vct(attacker={attacker})",
                    tuple(py) if py is not None else None, sw)

    # ---- MCTSEngine helper ops ----
    # See DiffTestCLI comment: full MCTS loop is intentionally NOT diff
    # tested. We verify the pieces that determine move selection in
    # every position (priors, leaf evals) and the early-exit shortcuts.

    # 15. _softmax_prior — bit-exact on random scored lists. numpy.exp
    # and Foundation.exp both go through libm on macos-15; any drift
    # would be a real compiler/platform bug.
    for temp in (0.3, 1.0):
        cells = rng.sample(
            [(r, c) for r in range(BOARD_SIZE) for c in range(BOARD_SIZE)],
            k=min(10, BOARD_SIZE * BOARD_SIZE))
        scored = [((r, c), rng.uniform(-100, 5000)) for (r, c) in cells]
        py_probs = _softmax_prior(scored, temperature=temp)
        sw_resp = call_swift(cli, {
            "op": "softmax_prior",
            "scored": [[r, c, s] for (r, c), s in scored],
            "temperature": temp,
        })
        sw_probs = {(int(row[0]), int(row[1])): row[2]
                    for row in sw_resp.get("probs", [])}
        for (r, c), py_p in py_probs.items():
            diff.expect_close(f"softmax_prior(t={temp}).({r},{c})",
                              py_p, sw_probs.get((r, c)))

    # 16. PUCT formula — scalar; independent from board state so we
    # synthesise a few node configurations.
    for scenario in [
        # (prior, wins, visits, parent_visits, c_puct)
        (0.1,  0.0,  0,  0,   1.4),
        (0.3,  5.0, 10, 100,  1.4),
        (0.8, 12.0, 50, 500,  2.5),
        (0.05, 0.0,  0, 42,   1.0),
    ]:
        prior, wins, visits, pvisits, c_puct = scenario
        # Build a Python node mirror + call .puct().
        from ai.mcts_engine import MCTSNode
        parent = MCTSNode(None, None, BLACK)
        parent.visits = pvisits
        child = MCTSNode(parent, (0, 0), WHITE, prior=prior)
        child.visits = visits
        child.wins = wins
        py_score = float(child.puct(c_puct))
        sw_resp = call_swift(cli, {
            "op": "puct", "prior": prior, "wins": wins,
            "visits": visits, "parent_visits": pvisits, "c_puct": c_puct,
        })
        sw_score = float(sw_resp.get("score", float('nan')))
        diff.expect_close(f"puct({prior},{wins},{visits},{pvisits},{c_puct})",
                          py_score, sw_score)

    # 17. static_leaf_value — integer. Use raw board + player; both
    # sides mutate their copy of the board internally.
    g17 = GameLogic()
    g17.board = board_np.copy()
    g17.current_player = player
    py_winner = int(MCTSEngine()._static_leaf_value(g17))
    sw_resp = call_swift(cli, {
        "op": "static_leaf_value", "board": board, "player": player,
    })
    sw_winner = int(sw_resp.get("winner", -999))
    diff.expect(f"static_leaf_value(p={player})", py_winner, sw_winner)

    # 18. continuous_leaf_value — float scalar, both perspectives.
    for persp in (BLACK, WHITE):
        g18 = GameLogic()
        g18.board = board_np.copy()
        g18.current_player = player
        py_v = float(MCTSEngine()._continuous_leaf_value(g18, persp))
        sw_resp = call_swift(cli, {
            "op": "continuous_leaf_value", "board": board,
            "player": player, "perspective": persp,
        })
        sw_v = float(sw_resp.get("value", float('nan')))
        diff.expect_close(f"continuous_leaf_value(p={player},persp={persp})",
                          py_v, sw_v)

    # 19. compute_priors in pattern-only mode. Sparse dict keyed "r,c".
    g19 = GameLogic()
    g19.board = board_np.copy()
    g19.current_player = player
    cands = g19.get_nearby_moves(2)
    py_priors = MCTSEngine()._compute_priors(g19, cands, player)
    py_map = {f"{r},{c}": float(v) for (r, c), v in py_priors.items()}
    sw_resp = call_swift(cli, {
        "op": "compute_priors_pattern",
        "board": board, "player": player,
    })
    sw_map = {k: float(v) for k, v in (sw_resp.get("priors") or {}).items()}
    diff.expect(f"compute_priors.keys(p={player})",
                sorted(py_map.keys()), sorted(sw_map.keys()))
    for key, py_v in py_map.items():
        diff.expect_close(f"compute_priors(p={player}).{key}",
                          py_v, sw_map.get(key))

    # 20. chooseMove shortcut equality — only when VCF or VCT returns a
    # forced win for SOME side, or when an immediate win/block exists.
    # In those cases both engines take the same deterministic branch and
    # must agree. Non-shortcut positions depend on the stochastic MCTS
    # loop and are not compared.
    shortcut = False
    g20 = GameLogic()
    g20.board = board_np.copy()
    g20.current_player = player
    opponent = WHITE if player == BLACK else BLACK
    # Immediate win / block?
    for r, c in g20.get_nearby_moves(2):
        for who in (player, opponent):
            g20.board[r][c] = who
            if g20._check_win(r, c):
                shortcut = True
            g20.board[r][c] = 0
        if shortcut:
            break
    # VCF / VCT for either side?
    if not shortcut:
        if (find_vcf([row[:] for row in board], player, max_depth=10)
                is not None
                or find_vcf([row[:] for row in board], opponent, max_depth=10)
                is not None
                or find_vct([row[:] for row in board], player, max_depth=6)
                is not None
                or find_vct([row[:] for row in board], opponent, max_depth=6)
                is not None):
            shortcut = True

    if shortcut:
        py_move = tuple(MCTSEngine(simulations=1).choose_move(g20))
        sw_resp = call_swift(cli, {
            "op": "mcts_choose_move", "board": board, "player": player,
            "simulations": 1,
        })
        sw_raw = sw_resp.get("move")
        sw_move = tuple(sw_raw) if sw_raw else None
        diff.expect(f"mcts_choose_move.shortcut(p={player})",
                    py_move, sw_move)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--cases', type=int, default=50)
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--cli', default='./diff_test_cli')
    args = parser.parse_args()

    if not os.path.exists(args.cli):
        print(f"CLI not found: {args.cli}. Run build_cli.sh first.")
        sys.exit(2)

    rng = random.Random(args.seed)
    diff = Diff()
    for i in range(args.cases):
        test_case(rng, args.cli, diff)
        if (i + 1) % 10 == 0:
            print(f"  [{i + 1}/{args.cases}] {diff.checks} checks, "
                  f"{len(diff.mismatches)} mismatches so far")

    rc = diff.summary(args.cases)
    sys.exit(rc)


if __name__ == '__main__':
    main()
