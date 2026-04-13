#!/usr/bin/env python3
"""Unit tests for Python AI components."""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

passed = 0
failed = 0


def assert_eq(actual, expected, msg):
    global passed, failed
    if actual == expected:
        passed += 1
        print(f"  PASS: {msg}")
    else:
        failed += 1
        print(f"  FAIL: {msg} (expected {expected}, got {actual})")


def assert_true(val, msg):
    assert_eq(bool(val), True, msg)


def test_game_logic():
    print("[GameLogic]")
    from ai.game_logic import GameLogic, BLACK, WHITE, EMPTY, BOARD_SIZE

    g = GameLogic()
    assert_eq(g.board.shape, (15, 15), "board is 15x15")
    assert_eq(g.current_player, BLACK, "black goes first")

    ok = g.place_stone(7, 7)
    assert_true(ok, "place stone at center")
    assert_eq(g.board[7][7], BLACK, "center is black")
    assert_eq(g.current_player, WHITE, "white's turn")

    # Win detection
    g.reset()
    for i in range(5):
        g.place_stone(0, i)  # black
        if i < 4:
            g.place_stone(1, i)  # white
    assert_true(g.game_over, "game over after 5 in a row")
    assert_eq(g.winner, BLACK, "black wins")

    # Tensor conversion
    g.reset()
    g.place_stone(7, 7)
    tensor = g.to_tensor(WHITE)
    assert_eq(tensor.shape, (2, 15, 15), "tensor shape is (2,15,15)")
    assert_eq(tensor[1][7][7], 1.0, "opponent channel has black stone")


def test_mcts():
    print("[MCTS]")
    from ai.game_logic import GameLogic, BLACK, WHITE
    from ai.mcts_engine import MCTSEngine

    g = GameLogic()
    g.board[5][3] = BLACK
    g.board[5][4] = BLACK
    g.board[5][5] = BLACK
    g.board[5][6] = BLACK
    g.board[6][3] = WHITE
    g.board[6][4] = WHITE
    g.current_player = BLACK

    mcts = MCTSEngine(simulations=100)
    move = mcts.choose_move(g)
    wins = move in [(5, 7), (5, 2)]
    assert_true(wins, f"MCTS finds winning move at {move}")


def test_protocol():
    print("[Protocol]")
    from protocol import encode, decode_from_buffer

    msg = {"cmd": "move", "row": 7, "col": 8}
    data = encode(msg)
    assert_true(len(data) > 4, "encoded data has length prefix")

    decoded, remaining = decode_from_buffer(data)
    assert_eq(decoded["cmd"], "move", "decoded cmd matches")
    assert_eq(decoded["row"], 7, "decoded row matches")
    assert_eq(len(remaining), 0, "no remaining data")

    # Partial buffer
    decoded, remaining = decode_from_buffer(data[:3])
    assert_eq(decoded, None, "partial buffer returns None")


def test_model():
    print("[Model]")
    try:
        import torch
        from nn.model import ModelWrapper
        from ai.game_logic import GameLogic, BLACK

        model = ModelWrapper(device="cpu")
        g = GameLogic()
        g.place_stone(7, 7)

        policy, value = model.predict(g)
        assert_eq(policy.shape, (225,), f"policy shape is (225,)")
        assert_true(-1.0 <= value <= 1.0, f"value in [-1,1]: {value:.4f}")
        assert_true(abs(policy.sum() - 1.0) < 0.01, f"policy sums to ~1: {policy.sum():.4f}")
        print(f"  INFO: device=cpu, value={value:.4f}")
    except ImportError:
        print("  SKIP: torch not installed")


if __name__ == '__main__':
    print("=== Python AI Unit Tests ===\n")
    test_game_logic()
    test_mcts()
    test_protocol()
    test_model()
    print(f"\n=== Results: {passed} passed, {failed} failed ===")
    sys.exit(1 if failed > 0 else 0)
