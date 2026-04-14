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

    total_params = sum(p.numel() for p in model.parameters())
    expected_mb = total_params * 4 / (1024 * 1024)
    print(f"Model parameters: {total_params:,}  (~{expected_mb:.1f} MB in fp32)")
    print(f"PyTorch version: {torch.__version__}")

    dummy_input = torch.randn(1, input_channels, 15, 15)

    os.makedirs(os.path.dirname(output_path) or '.', exist_ok=True)
    # Force the legacy (non-dynamo) exporter. In PyTorch 2.5+ the default
    # dispatches to torch.onnx.dynamo_export which can emit an empty shell
    # if onnxscript fails, producing a tiny file.
    torch.onnx.export(
        model, dummy_input, output_path,
        input_names=['board'],
        output_names=['policy', 'value'],
        dynamic_axes={'board': {0: 'batch'}},
        opset_version=17,
        dynamo=False,
    )

    # If torch emitted external data (model.onnx + model.onnx.data),
    # collapse it back into a single self-contained .onnx file.
    data_sidecar = output_path + ".data"
    if os.path.exists(data_sidecar):
        print(f"Detected external weights sidecar: {data_sidecar}")
        import onnx
        onnx_model = onnx.load(output_path)  # auto-loads sidecar
        onnx.save_model(onnx_model, output_path, save_as_external_data=False)
        os.remove(data_sidecar)
        print(f"  Embedded weights into {output_path}, removed sidecar.")

    size_kb = os.path.getsize(output_path) / 1024
    print(f"Exported ONNX model to {output_path} ({size_kb:.0f} KB)")
    print(f"  Input shape: (batch, {input_channels}, 15, 15)")
    if size_kb < expected_mb * 1024 * 0.5:
        print(f"  WARNING: file is much smaller than expected {expected_mb:.1f} MB.")


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
