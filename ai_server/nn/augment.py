"""Data augmentation via 8-fold board symmetry.

Gomoku is symmetric under the dihedral group D4 (4 rotations × mirror).
Each training sample can be expanded 8x without changing its semantics.
This gives a free 8x multiplier on training data size, which is the
single biggest lever for training quality on small datasets.

Rotations and mirrors are applied consistently to both the state tensor
and the policy target (which is a flattened 15×15 distribution).
"""

import numpy as np

BOARD_SIZE = 15


def _policy_to_2d(policy_flat: np.ndarray) -> np.ndarray:
    return policy_flat.reshape(BOARD_SIZE, BOARD_SIZE)


def _policy_to_flat(policy_2d: np.ndarray) -> np.ndarray:
    return policy_2d.reshape(BOARD_SIZE * BOARD_SIZE)


def augment_sample(state: np.ndarray, policy: np.ndarray, value: float):
    """Yield (state, policy, value) for all 8 symmetries of a single sample.

    state:  np.ndarray of shape (C, 15, 15)
    policy: np.ndarray of shape (225,) probability distribution
    value:  float in [-1, +1]  (invariant under symmetry)
    """
    results = []
    p2d = _policy_to_2d(policy)
    for k in range(4):  # 4 rotations: 0, 90, 180, 270 degrees
        s_rot = np.rot90(state, k=k, axes=(-2, -1)).copy()
        p_rot = np.rot90(p2d, k=k).copy()
        results.append((s_rot, _policy_to_flat(p_rot), float(value)))
        # Mirror (horizontal flip of columns)
        s_mir = np.flip(s_rot, axis=-1).copy()
        p_mir = np.flip(p_rot, axis=-1).copy()
        results.append((s_mir, _policy_to_flat(p_mir), float(value)))
    return results


def augment_dataset(samples):
    """Apply 8x augmentation to a whole dataset.

    samples: iterable of (state, policy, value)
    returns: list of augmented samples (8x input length)
    """
    out = []
    for s, p, v in samples:
        out.extend(augment_sample(s, p, v))
    return out
