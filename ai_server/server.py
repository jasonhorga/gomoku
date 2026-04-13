"""TCP server for Godot AI communication."""

import asyncio
import json
import logging
import os
import sys
import numpy as np

# Add parent to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from ai.game_logic import GameLogic, BOARD_SIZE, EMPTY, BLACK, WHITE
from ai.mcts_engine import MCTSEngine
from nn.model import ModelWrapper
from protocol import encode, decode_from_buffer

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)

HOST = '127.0.0.1'
PORT = 9877
WEIGHTS_DIR = os.path.join(os.path.dirname(__file__), 'data', 'weights')


class AIServer:
    def __init__(self):
        self.model = ModelWrapper()
        self.mcts = MCTSEngine(simulations=800, nn_model=self.model)
        self._load_latest_weights()

    def _load_latest_weights(self):
        """Load the latest generation weights if available."""
        if not os.path.exists(WEIGHTS_DIR):
            os.makedirs(WEIGHTS_DIR, exist_ok=True)
            logger.info("No weights found, using random initialization")
            return

        weight_files = sorted([f for f in os.listdir(WEIGHTS_DIR) if f.endswith('.pt')])
        if weight_files:
            path = os.path.join(WEIGHTS_DIR, weight_files[-1])
            self.model.load(path)
            logger.info(f"Loaded weights: {weight_files[-1]}")
        else:
            logger.info("No weights found, using random initialization")

    async def handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
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
                    response = self._handle_message(msg)
                    writer.write(encode(response))
                    await writer.drain()
        except Exception as e:
            logger.error(f"Error with client {addr}: {e}")
        finally:
            logger.info(f"Client disconnected: {addr}")
            writer.close()
            await writer.wait_closed()

    def _handle_message(self, msg: dict) -> dict:
        cmd = msg.get('cmd', '')

        if cmd == 'move':
            return self._handle_move(msg)
        elif cmd == 'status':
            return self._handle_status()
        else:
            return {"error": f"Unknown command: {cmd}"}

    def _handle_move(self, msg: dict) -> dict:
        board_data = msg.get('board', [])
        current = msg.get('current', BLACK)

        game = GameLogic()
        game.board = np.array(board_data, dtype=np.int8)
        game.current_player = current

        import time
        start = time.time()
        row, col = self.mcts.choose_move(game)
        elapsed = time.time() - start

        # Get evaluation
        _, value = self.model.predict(game)

        logger.info(f"Move: ({row},{col}) eval={value:.3f} time={elapsed:.2f}s")
        return {
            "row": row,
            "col": col,
            "eval": round(float(value), 4),
            "think_time": round(elapsed, 3)
        }

    def _handle_status(self) -> dict:
        weight_files = []
        if os.path.exists(WEIGHTS_DIR):
            weight_files = sorted([f for f in os.listdir(WEIGHTS_DIR) if f.endswith('.pt')])
        return {
            "cmd": "status_reply",
            "ready": True,
            "model_gen": len(weight_files),
            "device": str(self.model.device),
        }

    async def run(self):
        server = await asyncio.start_server(self.handle_client, HOST, PORT)
        logger.info(f"AI Server listening on {HOST}:{PORT}")
        async with server:
            await server.serve_forever()


def main():
    server = AIServer()
    asyncio.run(server.run())


if __name__ == '__main__':
    main()
