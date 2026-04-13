"""Pure game logic for Gomoku - Python mirror of GDScript version."""

import numpy as np

BOARD_SIZE = 15
EMPTY = 0
BLACK = 1
WHITE = 2

DIRECTIONS = [(0, 1), (1, 0), (1, 1), (1, -1)]


class GameLogic:
    def __init__(self):
        self.reset()

    def reset(self):
        self.board = np.zeros((BOARD_SIZE, BOARD_SIZE), dtype=np.int8)
        self.current_player = BLACK
        self.move_history = []
        self.game_over = False
        self.winner = EMPTY

    def place_stone(self, row: int, col: int) -> bool:
        if self.game_over:
            return False
        if row < 0 or row >= BOARD_SIZE or col < 0 or col >= BOARD_SIZE:
            return False
        if self.board[row][col] != EMPTY:
            return False

        self.board[row][col] = self.current_player
        self.move_history.append((row, col))

        if self._check_win(row, col):
            self.game_over = True
            self.winner = self.current_player
        elif len(self.move_history) >= BOARD_SIZE * BOARD_SIZE:
            self.game_over = True
            self.winner = EMPTY

        self.current_player = WHITE if self.current_player == BLACK else BLACK
        return True

    def _check_win(self, row: int, col: int) -> bool:
        player = self.board[row][col]
        for dr, dc in DIRECTIONS:
            count = 1
            count += self._count_dir(row, col, dr, dc, player)
            count += self._count_dir(row, col, -dr, -dc, player)
            if count >= 5:
                return True
        return False

    def _count_dir(self, row: int, col: int, dr: int, dc: int, player: int) -> int:
        count = 0
        r, c = row + dr, col + dc
        while 0 <= r < BOARD_SIZE and 0 <= c < BOARD_SIZE and self.board[r][c] == player:
            count += 1
            r += dr
            c += dc
        return count

    def copy(self):
        g = GameLogic()
        g.board = self.board.copy()
        g.current_player = self.current_player
        g.move_history = list(self.move_history)
        g.game_over = self.game_over
        g.winner = self.winner
        return g

    def get_valid_moves(self):
        """Return list of (row, col) for all empty cells."""
        moves = []
        for r in range(BOARD_SIZE):
            for c in range(BOARD_SIZE):
                if self.board[r][c] == EMPTY:
                    moves.append((r, c))
        return moves

    def get_nearby_moves(self, radius=2):
        """Return empty cells within radius of any placed stone."""
        candidates = set()
        for r in range(BOARD_SIZE):
            for c in range(BOARD_SIZE):
                if self.board[r][c] != EMPTY:
                    for dr in range(-radius, radius + 1):
                        for dc in range(-radius, radius + 1):
                            nr, nc = r + dr, c + dc
                            if 0 <= nr < BOARD_SIZE and 0 <= nc < BOARD_SIZE:
                                if self.board[nr][nc] == EMPTY:
                                    candidates.add((nr, nc))
        if not candidates and not self.move_history:
            candidates.add((7, 7))
        return list(candidates)

    def to_tensor(self, player: int) -> np.ndarray:
        """Convert board to neural network input tensor: 2 channels (own, opponent)."""
        opponent = WHITE if player == BLACK else BLACK
        own = (self.board == player).astype(np.float32)
        opp = (self.board == opponent).astype(np.float32)
        return np.stack([own, opp], axis=0)  # shape: (2, 15, 15)

    def to_tensor_9ch(self, player: int) -> np.ndarray:
        """9-channel input with pattern features for v2 CNN.

        Channels:
          0: own stones
          1: opponent stones
          2: self can make five (immediate win mask)
          3: self can make open_four
          4: self can make open_three
          5: opponent can make five (must block)
          6: opponent can make open_four
          7: opponent can make open_three
          8: last-move indicator (single 1.0 at the most recent move)
        Returns float32 array of shape (9, 15, 15).
        """
        # Import locally to avoid circular import
        from ai.pattern_eval import make_feature_planes

        opponent = WHITE if player == BLACK else BLACK
        own = (self.board == player).astype(np.float32)
        opp = (self.board == opponent).astype(np.float32)
        pattern_planes = make_feature_planes(self.board, player)  # (6, 15, 15)
        last_move_plane = np.zeros((BOARD_SIZE, BOARD_SIZE), dtype=np.float32)
        if self.move_history:
            lr, lc = self.move_history[-1]
            last_move_plane[lr, lc] = 1.0
        return np.concatenate(
            [own[None], opp[None], pattern_planes, last_move_plane[None]], axis=0
        )
