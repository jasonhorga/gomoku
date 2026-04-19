#!/usr/bin/env python3
"""Validate CoreML conversion against PyTorch/ONNX references.

Runs N random board positions through PyTorch, ONNX, and CoreML models,
then reports numerical drift. Used as a CI gate for the Swift iOS plugin:
if CoreML diverges too far from PyTorch, the plan shifts to ONNX Runtime
for iOS.

Baseline: ONNX vs PyTorch should be ~0 (both FP32). CoreML vs PyTorch
drift is from FP16 compute precision used for Neural Engine.

Usage:
    python3 validate_coreml.py \
        --pt data/weights/best_model.pt \
        --onnx data/weights/best_model.onnx \
        --mlpackage /tmp/GomokuNet.mlpackage \
        --filters 128 --blocks 6 --positions 100
"""

import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def random_board_input(rng, max_stones=40):
    """Build a random mid-game board via legal play; return (1,9,15,15) float32."""
    from ai.game_logic import GameLogic, BOARD_SIZE

    game = GameLogic()
    n_target = int(rng.integers(10, max_stones + 1))
    attempts = 0
    while len(game.move_history) < n_target and attempts < n_target * 10:
        attempts += 1
        if game.game_over:
            break
        r = int(rng.integers(0, BOARD_SIZE))
        c = int(rng.integers(0, BOARD_SIZE))
        game.place_stone(r, c)
    tensor = game.to_tensor_9ch(game.current_player)
    return tensor[None, ...].astype(np.float32)


def load_pt_model(pt_path, filters, blocks, in_channels):
    import torch
    from nn.model import GomokuNet

    model = GomokuNet(
        num_filters=filters, num_res_blocks=blocks, input_channels=in_channels
    )
    ckpt = torch.load(pt_path, map_location='cpu', weights_only=False)
    if isinstance(ckpt, dict) and 'state_dict' in ckpt:
        model.load_state_dict(ckpt['state_dict'])
    else:
        model.load_state_dict(ckpt)
    model.eval()
    return model


def pt_predict(model, x_np):
    import torch

    with torch.no_grad():
        log_policy, value = model(torch.from_numpy(x_np))
    return log_policy.numpy()[0], float(value.numpy()[0, 0])


def onnx_predict(session, x_np):
    # export_onnx.py names outputs 'policy' and 'value' but the network
    # actually emits log_softmax from its policy head — so 'policy' here
    # is log-policy. Treat it the same as pt_predict's first return.
    inputs = {session.get_inputs()[0].name: x_np}
    outputs = session.run(None, inputs)
    return outputs[0][0], float(outputs[1][0, 0])


def coreml_predict(mlmodel, x_np):
    # export_coreml.py names outputs 'log_policy' and 'value'.
    result = mlmodel.predict({'board': x_np})
    log_p = np.asarray(result['log_policy']).reshape(-1)
    val = float(np.asarray(result['value']).flatten()[0])
    return log_p, val


def stats(arr):
    a = np.asarray(arr, dtype=np.float64)
    return {
        'mean': float(a.mean()),
        'max': float(a.max()),
        'p95': float(np.percentile(a, 95)),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pt', required=True)
    parser.add_argument('--onnx', required=True)
    parser.add_argument('--mlpackage', required=True)
    parser.add_argument('--filters', type=int, default=128)
    parser.add_argument('--blocks', type=int, default=6)
    parser.add_argument('--input-channels', type=int, default=9)
    parser.add_argument('--positions', type=int, default=100)
    parser.add_argument('--seed', type=int, default=42)
    # Thresholds chosen generously for FP16 drift; tighten once we see actuals.
    parser.add_argument('--prob-l2-thresh', type=float, default=5e-3)
    parser.add_argument('--prob-max-thresh', type=float, default=2e-2)
    parser.add_argument('--value-thresh', type=float, default=1e-2)
    args = parser.parse_args()

    rng = np.random.default_rng(args.seed)

    print(f"Loading PyTorch:  {args.pt}")
    pt_model = load_pt_model(
        args.pt, args.filters, args.blocks, args.input_channels
    )

    print(f"Loading ONNX:     {args.onnx}")
    import onnxruntime

    onnx_session = onnxruntime.InferenceSession(
        args.onnx, providers=['CPUExecutionProvider']
    )

    print(f"Loading CoreML:   {args.mlpackage}")
    import coremltools as ct

    mlmodel = ct.models.MLModel(args.mlpackage)

    print(f"Running {args.positions} random positions...\n")

    cm_prob_l2 = []
    cm_prob_max = []
    cm_value_diff = []
    onnx_prob_l2 = []
    onnx_value_diff = []

    for i in range(args.positions):
        x = random_board_input(rng)
        pt_lp, pt_v = pt_predict(pt_model, x)
        onnx_lp, onnx_v = onnx_predict(onnx_session, x)
        cm_lp, cm_v = coreml_predict(mlmodel, x)

        # Compare in probability space (more interpretable than log space).
        pt_p = np.exp(pt_lp)
        cm_p = np.exp(cm_lp)
        onnx_p = np.exp(onnx_lp)

        cm_prob_l2.append(float(np.linalg.norm(cm_p - pt_p)))
        cm_prob_max.append(float(np.abs(cm_p - pt_p).max()))
        cm_value_diff.append(abs(cm_v - pt_v))

        onnx_prob_l2.append(float(np.linalg.norm(onnx_p - pt_p)))
        onnx_value_diff.append(abs(onnx_v - pt_v))

        if i < 3 or i % 25 == 24 or i == args.positions - 1:
            print(
                f"  [{i:3d}]  CM-vs-PT: prob L2={cm_prob_l2[-1]:.4e} "
                f"max={cm_prob_max[-1]:.4e} value={cm_value_diff[-1]:.4e}"
            )

    cm_l2 = stats(cm_prob_l2)
    cm_max = stats(cm_prob_max)
    cm_val = stats(cm_value_diff)
    ox_l2 = stats(onnx_prob_l2)
    ox_val = stats(onnx_value_diff)

    print("\n=== CoreML vs PyTorch (the actual test) ===")
    print(
        f"  prob L2:     mean={cm_l2['mean']:.4e}  p95={cm_l2['p95']:.4e}  "
        f"max={cm_l2['max']:.4e}   (thresh {args.prob_l2_thresh:.2e})"
    )
    print(
        f"  prob max:    mean={cm_max['mean']:.4e}  p95={cm_max['p95']:.4e}  "
        f"max={cm_max['max']:.4e}   (thresh {args.prob_max_thresh:.2e})"
    )
    print(
        f"  value diff:  mean={cm_val['mean']:.4e}  p95={cm_val['p95']:.4e}  "
        f"max={cm_val['max']:.4e}   (thresh {args.value_thresh:.2e})"
    )

    print("\n=== ONNX vs PyTorch (sanity baseline, should be near zero) ===")
    print(
        f"  prob L2:     mean={ox_l2['mean']:.4e}  max={ox_l2['max']:.4e}"
    )
    print(
        f"  value diff:  mean={ox_val['mean']:.4e}  max={ox_val['max']:.4e}"
    )

    failures = []
    if cm_l2['max'] > args.prob_l2_thresh:
        failures.append(
            f"CoreML prob L2 max {cm_l2['max']:.4e} > threshold {args.prob_l2_thresh:.2e}"
        )
    if cm_max['max'] > args.prob_max_thresh:
        failures.append(
            f"CoreML prob max-abs {cm_max['max']:.4e} > threshold {args.prob_max_thresh:.2e}"
        )
    if cm_val['max'] > args.value_thresh:
        failures.append(
            f"CoreML value max-abs {cm_val['max']:.4e} > threshold {args.value_thresh:.2e}"
        )

    if failures:
        print("\n[FAIL] CoreML conversion diverges from PyTorch:")
        for f in failures:
            print(f"  - {f}")
        print(
            "\nPlan B: re-export without FP16 (compute_precision=FLOAT32) "
            "or fall back to ONNX Runtime for iOS."
        )
        sys.exit(1)

    print("\n[PASS] CoreML conversion within tolerance — safe to proceed with Swift plugin.")
    sys.exit(0)


if __name__ == '__main__':
    main()
