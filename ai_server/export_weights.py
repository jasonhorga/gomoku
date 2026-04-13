#!/usr/bin/env python3
"""Export PyTorch model weights to JSON for GDScript CNN inference."""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def export(input_path: str, output_path: str, num_filters: int = 64, num_res_blocks: int = 3):
    import torch
    from nn.model import GomokuNet

    # Load model
    model = GomokuNet(num_filters=num_filters, num_res_blocks=num_res_blocks)
    state = torch.load(input_path, map_location='cpu', weights_only=True)
    model.load_state_dict(state)
    model.eval()

    # Convert all parameters to lists
    weights = {}
    for name, param in model.named_parameters():
        weights[name] = param.detach().cpu().numpy().tolist()

    # Also export running mean/var from BatchNorm layers
    for name, buf in model.named_buffers():
        if 'running_mean' in name or 'running_var' in name or 'num_batches_tracked' in name:
            weights[name] = buf.detach().cpu().numpy().tolist()

    # Save model architecture info
    meta = {
        "num_filters": num_filters,
        "num_res_blocks": num_res_blocks,
        "board_size": 15,
    }

    output = {"meta": meta, "weights": weights}

    os.makedirs(os.path.dirname(output_path) or '.', exist_ok=True)
    with open(output_path, 'w') as f:
        json.dump(output, f)

    size_mb = os.path.getsize(output_path) / 1024 / 1024
    print(f"Exported {len(weights)} tensors to {output_path} ({size_mb:.1f} MB)")


def main():
    parser = argparse.ArgumentParser(description='Export PyTorch weights to JSON')
    parser.add_argument('input', help='Path to .pt weights file')
    parser.add_argument('-o', '--output', default=None, help='Output JSON path')
    parser.add_argument('--filters', type=int, default=64, help='Number of filters')
    parser.add_argument('--blocks', type=int, default=3, help='Number of ResBlocks')
    args = parser.parse_args()

    if args.output is None:
        args.output = args.input.replace('.pt', '.json')

    export(args.input, args.output, args.filters, args.blocks)


if __name__ == '__main__':
    main()
