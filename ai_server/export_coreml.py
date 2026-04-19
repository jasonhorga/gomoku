#!/usr/bin/env python3
"""Convert the PyTorch Gomoku model to a CoreML .mlpackage for iOS inference.

Run this on macOS (coremltools supports Linux but MIL/Neural Engine
verification needs Mac). The output lives at

    assets/GomokuNet.mlpackage

which the iOS export bundles into the .app. The iOS plugin loads it via
[[MLModel compileModelAtURL:...]] → [[MLModel modelWithContentsOfURL:...]].

Prereqs:
    pip install torch coremltools

Usage:
    python export_coreml.py data/weights/big_iter_1.pt \
        --filters 128 --blocks 6 \
        -o ../assets/GomokuNet.mlpackage
"""

import argparse
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def convert(pt_path: str, out_path: str, num_filters: int, num_blocks: int,
            input_channels: int = 9) -> None:
    import torch
    import coremltools as ct
    from nn.model import GomokuNet

    model = GomokuNet(
        num_filters=num_filters,
        num_res_blocks=num_blocks,
        input_channels=input_channels,
    )

    ckpt = torch.load(pt_path, map_location='cpu', weights_only=False)
    if isinstance(ckpt, dict) and 'state_dict' in ckpt:
        model.load_state_dict(ckpt['state_dict'])
    else:
        model.load_state_dict(ckpt)
    model.eval()

    # Trace the model with a fixed-shape input. CoreML prefers static shapes
    # for maximum Neural Engine coverage; we only ever run one board at a time.
    example = torch.randn(1, input_channels, 15, 15)
    traced = torch.jit.trace(model, example)

    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(
            name="board",
            shape=(1, input_channels, 15, 15),
            dtype=float,
        )],
        outputs=[
            ct.TensorType(name="log_policy"),
            ct.TensorType(name="value"),
        ],
        # mlprogram requires iOS 15+. iOS 14/15 cover the same devices
        # (iPhone 6s onward), so bumping costs nothing in reach.
        minimum_deployment_target=ct.target.iOS15,
        compute_precision=ct.precision.FLOAT16,  # neural engine prefers fp16
        convert_to="mlprogram",  # mlpackage (not the old .mlmodel format)
    )

    mlmodel.short_description = (
        "Gomoku policy+value network. "
        "Input: (1,9,15,15) float32 board + pattern planes + last-move plane. "
        "Outputs: log_policy (1,225), value (1,1)."
    )

    if os.path.exists(out_path):
        shutil.rmtree(out_path) if os.path.isdir(out_path) else os.remove(out_path)
    mlmodel.save(out_path)

    total = sum(p.numel() for p in model.parameters())
    size_mb = _dir_size_mb(out_path) if os.path.isdir(out_path) else os.path.getsize(out_path) / (1024 * 1024)
    print(f"Saved {out_path}")
    print(f"  Parameters: {total:,}")
    print(f"  Size on disk: {size_mb:.2f} MB (fp16)")
    print(f"  Input shape: (1, {input_channels}, 15, 15)")


def _dir_size_mb(path: str) -> float:
    total = 0
    for root, _, files in os.walk(path):
        for f in files:
            total += os.path.getsize(os.path.join(root, f))
    return total / (1024 * 1024)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('input', help='Path to .pt weights file')
    parser.add_argument('-o', '--output', default='../assets/GomokuNet.mlpackage')
    parser.add_argument('--filters', type=int, default=128)
    parser.add_argument('--blocks', type=int, default=6)
    parser.add_argument('--input-channels', type=int, default=9)
    args = parser.parse_args()
    convert(args.input, args.output, args.filters, args.blocks, args.input_channels)


if __name__ == '__main__':
    main()
