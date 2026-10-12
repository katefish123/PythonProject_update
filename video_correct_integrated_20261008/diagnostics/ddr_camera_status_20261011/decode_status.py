"""Decode D205 state overlaid by the physical DDR diagnostic FPGA image."""
from pathlib import Path
import argparse
import json
from PIL import Image

def decode(path):
    frame = Image.open(path).convert("RGB")
    if frame.size != (1920, 1080):
        raise ValueError("A fitted native 1920x1080 OBS frame is required")
    bits = []
    for row in range(32):
        for col in range(16):
            red, green, blue = frame.getpixel((60 + 120 * col, 725 + 10 * row))
            if max(red, green) < 60 or abs(red - green) < 50:
                raise ValueError(f"Unreadable D205 status cell at row={row},col={col}")
            bits.append("1" if green > red else "0")
    word = int("".join(bits), 2)
    if word >> 496 != 0xD205:
        raise ValueError("Wrong DDR diagnostic signature")
    flags = (word >> 480) & 0xffff
    rx = (word >> 384) & ((1 << 96) - 1)
    proc = (word >> 256) & ((1 << 128) - 1)
    marker = (word >> 64) & ((1 << 192) - 1)
    ui = word & ((1 << 64) - 1)
    names = ["clocks_ready", "ddr_lock", "ddr_ready", "selftest_passed", "selftest_failed", "engine_fault", "phy_fail", "align_error",
        "rx_done", "tx_done", "config_error", "ack_error", "image_valid", "frame_error", "input_wait", "underrun"]
    result = {name: bool((flags >> (15-i)) & 1) for i, name in enumerate(names)}
    result.update(frame=str(path), word_hex=f"{word:0128x}",
        rx_good_captures=rx >> 80, rx_bad_captures=(rx >> 64) & 0xffff,
        last_capture_samples=(rx >> 40) & 0xffffff, last_capture_lines=(rx >> 24) & 0xffff,
        last_capture_flags=(rx >> 16) & 0xff, last_capture_packets=rx & 0xffff,
        proc_flags=(proc >> 112) & 0xffff, good_results=(proc >> 80) & 0xffffffff,
        rejected_results=(proc >> 48) & 0xffffffff, last_failure=(proc >> 40) & 0xff,
        session_state=(proc >> 36) & 15, processor_state=(proc >> 32) & 15, processor_cycles=proc & 0xffffffff,
        marker_flags=(marker >> 176) & 0xffff,
        marker_counts=[(marker >> shift) & 0xffff for shift in [160, 144, 128, 112]],
        marker_x_spans=[(marker >> shift) & 0xfff for shift in [100, 88, 76, 64]],
        marker_y_spans=[(marker >> shift) & 0xfff for shift in [52, 40, 28, 16]],
        ui_packets_seen=(ui >> 40) & 0xffffff, ui_packets_written=(ui >> 16) & 0xffffff,
        ui_writer_state=(ui >> 13) & 7, ui_frame_bad=bool((ui >> 12) & 1), ui_rx_capture_ok=bool((ui >> 11) & 1),
        ui_empty_quiet=ui & 0xff)
    if marker & 0xffff:
        raise ValueError("Unexpected nonzero reserved marker bits")
    return result

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("frame", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    text = json.dumps(decode(args.frame), ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.write_text(text, encoding="utf-8")
    print(text)
