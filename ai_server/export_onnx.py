#!/usr/bin/env python3
"""Export PyTorch model to ONNX format for lightweight inference."""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def export(input_path: str, output_path: str, num_filters=32,
           num_res_blocks=2, input_channels=9):
    import torch
    from nn.model import GomokuNet

    model = GomokuNet(
        num_filters=num_filters,
        num_res_blocks=num_res_blocks,
        input_channels=input_channels,
    )

    # Support both v2 checkpoint format (dict with state_dict + metadata)
    # and legacy raw state_dict format.
    ckpt = torch.load(input_path, map_location='cpu', weights_only=False)
    if isinstance(ckpt, dict) and 'state_dict' in ckpt:
        model.load_state_dict(ckpt['state_dict'])
        # Echo meta if present, for safety
        meta = {k: v for k, v in ckpt.items() if k != 'state_dict'}
        print(f"Loaded v2 checkpoint. Metadata: {meta}")
    else:
        model.load_state_dict(ckpt)
    model.eval()

    dummy_input = torch.randn(1, input_channels, 15, 15)

    os.makedirs(os.path.dirname(output_path) or '.', exist_ok=True)
    torch.onnx.export(
        model, dummy_input, output_path,
        input_names=['board'],
        output_names=['policy', 'value'],
        dynamic_axes={'board': {0: 'batch'}},
        opset_version=13,
    )

    size_kb = os.path.getsize(output_path) / 1024
    print(f"Exported ONNX model to {output_path} ({size_kb:.0f} KB)")
    print(f"  Input shape: (batch, {input_channels}, 15, 15)")


def main():
    parser = argparse.ArgumentParser(description='Export model to ONNX')
    parser.add_argument('input', help='Path to .pt weights file')
    parser.add_argument('-o', '--output', default='data/weights/model.onnx')
    parser.add_argument('--filters', type=int, default=32)
    parser.add_argument('--blocks', type=int, default=2)
    parser.add_argument('--input-channels', type=int, default=9)
    args = parser.parse_args()
    export(args.input, args.output, args.filters, args.blocks, args.input_channels)


if __name__ == '__main__':
    main()
