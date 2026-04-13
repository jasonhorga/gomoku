#!/usr/bin/env python3
"""
Lightweight AI server using ONNX Runtime (no PyTorch needed).
For bundling with the game via PyInstaller.

Usage:
  python onnx_server.py                     # auto-find model.onnx
  python onnx_server.py --model path.onnx   # specify model
"""

import asyncio
import json
import logging
import os
import sys
import time
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from protocol import encode, decode_from_buffer

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)

HOST = '127.0.0.1'
PORT = 9877
BOARD_SIZE = 15
EMPTY, BLACK, WHITE = 0, 1, 2
DIRECTIONS = [(0, 1), (1, 0), (1, 1), (1, -1)]


def _make_pattern_planes(board, current_player):
    """Mirror of ai.pattern_eval.make_feature_planes (inlined to keep
    onnx_server.py self-contained for PyInstaller bundling)."""
    opponent = WHITE if current_player == BLACK else BLACK
    planes = np.zeros((6, BOARD_SIZE, BOARD_SIZE), dtype=np.float32)

    def _threats_for(r, c, who):
        """Returns dict of which patterns placing 'who' at (r,c) would make."""
        result = {"five": False, "open_four": False,
                  "half_four": False, "open_three": False,
                  "half_three": False}
        for dr, dc in DIRECTIONS:
            count = 1
            open_ends = 0
            # positive direction
            rr, cc = r + dr, c + dc
            while 0 <= rr < BOARD_SIZE and 0 <= cc < BOARD_SIZE and board[rr][cc] == who:
                count += 1
                rr += dr
                cc += dc
            if 0 <= rr < BOARD_SIZE and 0 <= cc < BOARD_SIZE and board[rr][cc] == EMPTY:
                open_ends += 1
            # negative direction
            rr, cc = r - dr, c - dc
            while 0 <= rr < BOARD_SIZE and 0 <= cc < BOARD_SIZE and board[rr][cc] == who:
                count += 1
                rr -= dr
                cc -= dc
            if 0 <= rr < BOARD_SIZE and 0 <= cc < BOARD_SIZE and board[rr][cc] == EMPTY:
                open_ends += 1

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

    for r in range(BOARD_SIZE):
        for c in range(BOARD_SIZE):
            if board[r][c] != EMPTY:
                continue
            self_t = _threats_for(r, c, current_player)
            opp_t = _threats_for(r, c, opponent)
            if self_t["five"]: planes[0, r, c] = 1.0
            if self_t["open_four"]: planes[1, r, c] = 1.0
            if self_t["open_three"]: planes[2, r, c] = 1.0
            if opp_t["five"]: planes[3, r, c] = 1.0
            if opp_t["open_four"]: planes[4, r, c] = 1.0
            if opp_t["open_three"]: planes[5, r, c] = 1.0
    return planes


class OnnxModel:
    def __init__(self, model_path: str):
        import onnxruntime as ort
        self.session = ort.InferenceSession(model_path)
        # Detect expected input channels from model shape
        in_shape = self.session.get_inputs()[0].shape
        self.input_channels = int(in_shape[1]) if len(in_shape) >= 2 and isinstance(in_shape[1], int) else 9
        logger.info(f"Loaded ONNX model: {model_path} (input_channels={self.input_channels})")

    def predict(self, board: np.ndarray, current_player: int,
                last_move=None):
        """Returns (policy[225], value)."""
        opponent = WHITE if current_player == BLACK else BLACK
        own = (board == current_player).astype(np.float32)
        opp = (board == opponent).astype(np.float32)

        if self.input_channels == 9:
            pattern_planes = _make_pattern_planes(board, current_player)
            last_plane = np.zeros((BOARD_SIZE, BOARD_SIZE), dtype=np.float32)
            if last_move is not None:
                lr, lc = last_move
                if 0 <= lr < BOARD_SIZE and 0 <= lc < BOARD_SIZE:
                    last_plane[lr, lc] = 1.0
            x = np.concatenate([
                own[None], opp[None], pattern_planes, last_plane[None]
            ], axis=0)[np.newaxis]  # (1, 9, 15, 15)
        else:
            x = np.stack([own, opp], axis=0)[np.newaxis]  # (1, 2, 15, 15)

        log_policy, value = self.session.run(None, {'board': x})

        policy = np.exp(log_policy[0])
        policy = np.maximum(policy, 0)

        # Mask invalid moves
        valid = (board.flatten() == EMPTY).astype(np.float32)
        policy *= valid
        s = policy.sum()
        if s > 0:
            policy /= s
        else:
            policy = valid / valid.sum()

        return policy, float(value[0][0])


def check_win(board, row, col, player):
    for dr, dc in DIRECTIONS:
        count = 1
        for sign in [1, -1]:
            r, c = row + dr * sign, col + dc * sign
            while 0 <= r < BOARD_SIZE and 0 <= c < BOARD_SIZE and board[r][c] == player:
                count += 1
                r += dr * sign
                c += dc * sign
        if count >= 5:
            return True
    return False


def get_nearby_moves(board, radius=2):
    candidates = set()
    for r in range(BOARD_SIZE):
        for c in range(BOARD_SIZE):
            if board[r][c] != EMPTY:
                for dr in range(-radius, radius + 1):
                    for dc in range(-radius, radius + 1):
                        nr, nc = r + dr, c + dc
                        if 0 <= nr < BOARD_SIZE and 0 <= nc < BOARD_SIZE and board[nr][nc] == EMPTY:
                            candidates.add((nr, nc))
    if not candidates:
        candidates.add((7, 7))
    return list(candidates)


def choose_move(model: OnnxModel, board: np.ndarray, current_player: int,
                last_move=None):
    """Simple policy-guided move selection."""
    candidates = get_nearby_moves(board, 2)
    opponent = WHITE if current_player == BLACK else BLACK

    # Immediate win/block
    for r, c in candidates:
        board[r][c] = current_player
        if check_win(board, r, c, current_player):
            board[r][c] = EMPTY
            return r, c, 1.0
        board[r][c] = EMPTY

    for r, c in candidates:
        board[r][c] = opponent
        if check_win(board, r, c, opponent):
            board[r][c] = EMPTY
            return r, c, 0.0
        board[r][c] = EMPTY

    # Use neural network policy
    policy, value = model.predict(board, current_player, last_move=last_move)

    # Pick highest-probability valid move
    best_idx = -1
    best_prob = -1.0
    for r, c in candidates:
        idx = r * BOARD_SIZE + c
        if policy[idx] > best_prob:
            best_prob = policy[idx]
            best_idx = idx

    if best_idx >= 0:
        return best_idx // BOARD_SIZE, best_idx % BOARD_SIZE, value
    return 7, 7, 0.0


class OnnxServer:
    def __init__(self, model_path: str):
        self.model = OnnxModel(model_path)

    async def handle_client(self, reader, writer):
        addr = writer.get_extra_info('peername')
        logger.info(f"Client connected: {addr}")
        buffer = b''

        try:
            while True:
                data = await reader.read(4096)
                if not data:
                    break
                buffer += data

                while True:
                    msg, buffer = decode_from_buffer(buffer)
                    if msg is None:
                        break
                    response = self._handle(msg)
                    writer.write(encode(response))
                    await writer.drain()
        except Exception as e:
            logger.error(f"Error: {e}")
        finally:
            logger.info(f"Client disconnected: {addr}")
            writer.close()
            await writer.wait_closed()

    def _handle(self, msg):
        cmd = msg.get('cmd', '')
        if cmd == 'move':
            board = np.array(msg['board'], dtype=np.int8)
            current = msg.get('current', BLACK)
            # Optional: last move played (for the 9ch last-move plane)
            last_move = None
            if 'last_move' in msg and msg['last_move'] is not None:
                lm = msg['last_move']
                if isinstance(lm, (list, tuple)) and len(lm) == 2:
                    last_move = (int(lm[0]), int(lm[1]))
            t0 = time.time()
            row, col, value = choose_move(self.model, board, current, last_move=last_move)
            elapsed = time.time() - t0
            logger.info(f"Move: ({row},{col}) eval={value:.3f} time={elapsed:.3f}s")
            return {"row": row, "col": col, "eval": round(value, 4), "think_time": round(elapsed, 3)}
        elif cmd == 'status':
            return {"cmd": "status_reply", "ready": True, "backend": "onnx"}
        return {"error": f"Unknown: {cmd}"}

    async def run(self):
        server = await asyncio.start_server(self.handle_client, HOST, PORT)
        logger.info(f"ONNX AI Server on {HOST}:{PORT}")
        async with server:
            await server.serve_forever()


def find_model():
    """Find model.onnx in standard locations."""
    search = [
        os.path.join(os.path.dirname(__file__), 'data', 'weights', 'model.onnx'),
        os.path.join(os.path.dirname(__file__), 'model.onnx'),
        'model.onnx',
    ]
    # Also check next to executable (for PyInstaller bundle)
    if getattr(sys, 'frozen', False):
        base = os.path.dirname(sys.executable)
        search.insert(0, os.path.join(base, 'model.onnx'))
        search.insert(0, os.path.join(base, 'data', 'weights', 'model.onnx'))

    for p in search:
        if os.path.exists(p):
            return p
    return None


def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--model', default=None, help='Path to .onnx model')
    args = parser.parse_args()

    model_path = args.model or find_model()
    if not model_path:
        logger.error("No model.onnx found! Train first, then run export_onnx.py")
        sys.exit(1)

    server = OnnxServer(model_path)
    asyncio.run(server.run())


if __name__ == '__main__':
    main()
