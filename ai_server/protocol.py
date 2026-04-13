"""JSON protocol for Godot <-> Python AI communication."""

import json

# Message types
CMD_MOVE = "move"         # Request AI move
CMD_STATUS = "status"     # Query server status
CMD_TRAIN = "train"       # Start training
CMD_STOP = "stop"         # Stop training


def encode(msg: dict) -> bytes:
    """Encode a message as length-prefixed JSON."""
    data = json.dumps(msg).encode('utf-8')
    length = len(data)
    return length.to_bytes(4, 'big') + data


def decode_from_buffer(buffer: bytes) -> tuple:
    """
    Try to decode a message from buffer.
    Returns (message_dict, remaining_buffer) or (None, buffer) if incomplete.
    """
    if len(buffer) < 4:
        return None, buffer
    length = int.from_bytes(buffer[:4], 'big')
    if len(buffer) < 4 + length:
        return None, buffer
    data = buffer[4:4 + length]
    msg = json.loads(data.decode('utf-8'))
    return msg, buffer[4 + length:]
