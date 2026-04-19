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
import os
import random
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
AI_SERVER = os.path.abspath(os.path.join(HERE, '..', '..', 'ai_server'))
sys.path.insert(0, AI_SERVER)

from ai.game_logic import GameLogic, BOARD_SIZE, BLACK, WHITE  # noqa: E402


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

    # 1. nearby_moves — output is a set equality check
    for radius in (1, 2):
        g = GameLogic()
        import numpy as np
        g.board = np.array(board, dtype=np.int8)
        g.current_player = player
        py_moves = sorted(tuple(m) for m in g.get_nearby_moves(radius))
        sw_resp = call_swift(cli, {
            "op": "nearby_moves", "board": board, "player": player, "radius": radius,
        })
        sw_moves = sorted(tuple(m) for m in sw_resp.get("moves", []))
        diff.expect(f"nearby_moves(r={radius})", py_moves, sw_moves)

    # 2. valid_moves — same check
    g = GameLogic()
    import numpy as np
    g.board = np.array(board, dtype=np.int8)
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
    g_cnt.board = np.array(board, dtype=np.int8)
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
