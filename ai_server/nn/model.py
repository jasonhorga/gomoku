"""CNN model for Gomoku - AlphaZero-style dual head (policy + value).

v2 changes:
  - Configurable input channels (2 or 9). 9-channel default includes
    pre-computed pattern feature planes that dramatically reduce the
    learning difficulty (the net starts with Level-3 tactical awareness).
  - Default backbone increased from tiny (8f/1b) to small (32f/2b) - still
    fast (<1ms inference on M-series) but has enough capacity to learn.
  - Uses 9-channel tensor by default. Falls back to 2-channel for legacy
    checkpoints.
"""

import torch
import torch.nn as nn
import torch.nn.functional as F
import numpy as np
import os

BOARD_SIZE = 15


class GomokuNet(nn.Module):
    """
    Input:  (batch, C, 15, 15) where C = input_channels (2 or 9)
    Output: policy (batch, 225) log-probs
            value  (batch, 1) tanh
    """

    def __init__(self, num_filters=32, num_res_blocks=2, input_channels=9):
        super().__init__()
        self.num_filters = num_filters
        self.num_res_blocks = num_res_blocks
        self.input_channels = input_channels

        self.conv_input = nn.Sequential(
            nn.Conv2d(input_channels, num_filters, 3, padding=1),
            nn.BatchNorm2d(num_filters),
            nn.ReLU(),
        )

        self.res_blocks = nn.ModuleList([
            ResBlock(num_filters) for _ in range(num_res_blocks)
        ])

        # Policy head
        self.policy_head = nn.Sequential(
            nn.Conv2d(num_filters, 4, 1),
            nn.BatchNorm2d(4),
            nn.ReLU(),
            nn.Flatten(),
            nn.Linear(4 * BOARD_SIZE * BOARD_SIZE, BOARD_SIZE * BOARD_SIZE),
        )

        # Value head
        self.value_head = nn.Sequential(
            nn.Conv2d(num_filters, 2, 1),
            nn.BatchNorm2d(2),
            nn.ReLU(),
            nn.Flatten(),
            nn.Linear(2 * BOARD_SIZE * BOARD_SIZE, 64),
            nn.ReLU(),
            nn.Linear(64, 1),
            nn.Tanh(),
        )

    def forward(self, x):
        x = self.conv_input(x)
        for block in self.res_blocks:
            x = block(x)
        policy = self.policy_head(x)
        value = self.value_head(x)
        return F.log_softmax(policy, dim=1), value


class ResBlock(nn.Module):
    def __init__(self, num_filters):
        super().__init__()
        self.conv1 = nn.Conv2d(num_filters, num_filters, 3, padding=1)
        self.bn1 = nn.BatchNorm2d(num_filters)
        self.conv2 = nn.Conv2d(num_filters, num_filters, 3, padding=1)
        self.bn2 = nn.BatchNorm2d(num_filters)

    def forward(self, x):
        residual = x
        x = F.relu(self.bn1(self.conv1(x)))
        x = self.bn2(self.conv2(x))
        x = F.relu(x + residual)
        return x


class ModelWrapper:
    """Wraps GomokuNet for easy prediction and model management."""

    def __init__(self, device=None, num_filters=32, num_res_blocks=2,
                 input_channels=9):
        if device is None:
            if torch.backends.mps.is_available():
                self.device = torch.device("mps")
            elif torch.cuda.is_available():
                self.device = torch.device("cuda")
            else:
                self.device = torch.device("cpu")
        else:
            self.device = torch.device(device)

        self.num_filters = num_filters
        self.num_res_blocks = num_res_blocks
        self.input_channels = input_channels
        self.model = GomokuNet(
            num_filters=num_filters,
            num_res_blocks=num_res_blocks,
            input_channels=input_channels,
        ).to(self.device)
        self.model.eval()

    def _state_tensor(self, game):
        """Pick the tensor representation matching this model's input."""
        if self.input_channels == 9:
            return game.to_tensor_9ch(game.current_player)
        return game.to_tensor(game.current_player)

    def predict(self, game) -> tuple:
        """Returns (policy: np.ndarray[225], value: float)."""
        tensor = self._state_tensor(game)
        x = torch.from_numpy(tensor).unsqueeze(0).to(self.device)

        with torch.no_grad():
            log_policy, value = self.model(x)

        policy = torch.exp(log_policy).cpu().numpy()[0]
        value_scalar = value.cpu().item()

        # Mask invalid moves
        valid = np.zeros(BOARD_SIZE * BOARD_SIZE, dtype=np.float32)
        for r in range(BOARD_SIZE):
            for c in range(BOARD_SIZE):
                if game.board[r][c] == 0:
                    valid[r * BOARD_SIZE + c] = 1.0

        policy *= valid
        policy_sum = policy.sum()
        if policy_sum > 0:
            policy /= policy_sum
        else:
            policy = valid / valid.sum()

        return policy, value_scalar

    def save(self, path: str):
        os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
        torch.save({
            'state_dict': self.model.state_dict(),
            'num_filters': self.num_filters,
            'num_res_blocks': self.num_res_blocks,
            'input_channels': self.input_channels,
        }, path)

    def load(self, path: str):
        ckpt = torch.load(path, map_location=self.device, weights_only=False)
        if isinstance(ckpt, dict) and 'state_dict' in ckpt:
            # v2 format with metadata — rebuild net if architecture differs
            ckpt_nf = ckpt.get('num_filters', self.num_filters)
            ckpt_nb = ckpt.get('num_res_blocks', self.num_res_blocks)
            ckpt_ic = ckpt.get('input_channels', self.input_channels)
            if (ckpt_nf != self.num_filters or
                ckpt_nb != self.num_res_blocks or
                ckpt_ic != self.input_channels):
                # Reconstruct net to match the checkpoint shape
                self.num_filters = ckpt_nf
                self.num_res_blocks = ckpt_nb
                self.input_channels = ckpt_ic
                self.model = GomokuNet(
                    num_filters=ckpt_nf,
                    num_res_blocks=ckpt_nb,
                    input_channels=ckpt_ic,
                ).to(self.device)
            self.model.load_state_dict(ckpt['state_dict'])
        else:
            # legacy: raw state dict
            self.model.load_state_dict(ckpt)
        self.model.eval()

    def train_mode(self):
        self.model.train()

    def eval_mode(self):
        self.model.eval()

    def count_parameters(self):
        return sum(p.numel() for p in self.model.parameters())
