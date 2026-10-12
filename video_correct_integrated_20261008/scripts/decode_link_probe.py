"""Decode the fixed 60-cell status strip from a captured link-probe frame."""
import argparse
from io import BytesIO
import json
from pathlib import Path
from PIL import Image


def decode(path):
    frame = Image.open(BytesIO(path.read_bytes())).convert("RGB")
    if frame.size != (1920, 1080):
        raise ValueError(f"Expected 1920x1080, got {frame.size}")
    bits = []
    ambiguous = []
    for row in range(4):
        for col in range(15):
            red, green, _ = frame.getpixel((64 + 128 * col, 1045 + 10 * row))
            if max(red, green) < 50 or abs(red - green) < 40:
                ambiguous.append(row * 15 + col)
            bits.append("1" if green > red else "0")
    if any(cell < 20 for cell in ambiguous):
        raise ValueError("Frame has no readable link flags/width status strip")
    bit_string = "".join(bits)
    word = int(bit_string, 2)
    return {
        "frame": str(path), "word_hex": f"0x{word:015x}", "bits": bit_string,
        "init_done": bool((word >> 59) & 1),
        "ack_error": bool((word >> 58) & 1),
        "rx_clock_seen": bool((word >> 57) & 1),
        "de_seen": bool((word >> 56) & 1),
        "rx_width": (word >> 40) & 0xffff,
        "hs_lines": (word >> 24) & 0xffff,
        "sample_rgb": f"0x{word & 0xffffff:06x}",
        "ambiguous_color_cells": ambiguous,
        "coherent_snapshot": False,
        "measurement_note": "Original probe changes counters/RGB during display; hs_lines/sample_rgb are raw samples, not frame-size measurements.",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("frame", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = decode(args.frame)
    rendered = json.dumps(result, indent=2)
    if args.output:
        args.output.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)
