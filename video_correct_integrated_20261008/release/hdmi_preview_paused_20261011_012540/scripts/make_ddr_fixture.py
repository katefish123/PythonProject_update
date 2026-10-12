from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "results" / "ddr_fixture"
sys.path.insert(0, str(ROOT / "vendor" / "b" / "python"))
from brect.fixed import rectify_fixed
from brect.golden import detect_markers, homography

SRC_W, SRC_H = 640, 480
OUT_W, OUT_H = 320, 452
POINTS = [(200, 45), (465, 100), (435, 420), (180, 390)]
MARKER_RGB = [(255, 0, 0), (0, 255, 0), (255, 255, 0), (0, 0, 255)]


def write_hex(path: Path, pixels: np.ndarray) -> None:
    with path.open("w", encoding="ascii", newline="\n") as stream:
        for r, g, b in pixels.reshape(-1, 3):
            stream.write(f"{int(r):02x}{int(g):02x}{int(b):02x}\n")


def inverse_warp(plane: np.ndarray) -> np.ndarray:
    # Float H maps canonical output pixel coordinates to the requested marker
    # centers. Invert it independently and bilinearly paint the camera image.
    h = homography(POINTS, OUT_W, OUT_H)
    inv = np.linalg.inv(h)
    ys, xs = np.mgrid[0:SRC_H, 0:SRC_W]
    d = inv[2, 0] * xs + inv[2, 1] * ys + inv[2, 2]
    px = (inv[0, 0] * xs + inv[0, 1] * ys + inv[0, 2]) / d
    py = (inv[1, 0] * xs + inv[1, 1] * ys + inv[1, 2]) / d
    valid = (d > 0) & (px >= 0) & (px <= OUT_W - 1) & (py >= 0) & (py <= OUT_H - 1)
    x0 = np.clip(np.floor(px).astype(np.int32), 0, OUT_W - 1)
    y0 = np.clip(np.floor(py).astype(np.int32), 0, OUT_H - 1)
    x1, y1 = np.minimum(x0 + 1, OUT_W - 1), np.minimum(y0 + 1, OUT_H - 1)
    fx, fy = (px - x0)[..., None], (py - y0)[..., None]
    a, b = plane[y0, x0].astype(np.float64), plane[y0, x1].astype(np.float64)
    c, e = plane[y1, x0].astype(np.float64), plane[y1, x1].astype(np.float64)
    rgb = ((a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + e * fx) * fy)
    result = np.full((SRC_H, SRC_W, 3), 112, dtype=np.uint8)
    result[valid] = np.clip(np.floor(rgb[valid] + 0.5), 0, 255).astype(np.uint8)
    return result


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    paper = Image.new("RGB", (OUT_W, OUT_H), (232, 232, 232))
    draw = ImageDraw.Draw(paper)
    draw.rectangle((0, 0, OUT_W - 1, OUT_H - 1), outline=(60, 60, 60), width=2)
    # Straight, low-contrast table lines and print that should rectify straight.
    for x in (24, 72, 120, 168, 216, 264, 304):
        draw.line((x, 72, x, 428), fill=(197, 197, 197), width=1)
    for y in (72, 116, 160, 204, 248, 292, 336, 380, 428):
        draw.line((18, y, 302, y), fill=(197, 197, 197), width=1)
    try:
        title_font = ImageFont.truetype("arial.ttf", 16)
        text_font = ImageFont.truetype("arial.ttf", 11)
    except OSError:
        title_font = ImageFont.load_default()
        text_font = ImageFont.load_default()
    draw.text((26, 22), "FIELD CALIBRATION SHEET", fill=(45, 45, 45), font=title_font)
    draw.text((26, 48), "RGB / GEOMETRY TEST  |  320 x 452", fill=(80, 80, 80), font=text_font)
    draw.text((31, 86), "NORTH  01", fill=(60, 60, 60), font=text_font)
    draw.text((79, 130), "GRID  02", fill=(60, 60, 60), font=text_font)
    draw.text((127, 218), "ALIGNMENT", fill=(60, 60, 60), font=text_font)
    draw.text((175, 306), "SCALE  1:1", fill=(60, 60, 60), font=text_font)
    draw.text((223, 388), "SOUTH  04", fill=(60, 60, 60), font=text_font)
    plane = np.asarray(paper, dtype=np.uint8)
    source = inverse_warp(plane)
    source_img = Image.fromarray(source, "RGB")
    marker_draw = ImageDraw.Draw(source_img)
    for (cx, cy), color in zip(POINTS, MARKER_RGB):
        marker_draw.rectangle((cx - 4, cy - 4, cx + 4, cy + 4), fill=color)
    source = np.asarray(source_img, dtype=np.uint8)
    detected, stats = detect_markers(source)
    if detected is None or detected.tolist() != [list(p) for p in POINTS]:
        raise RuntimeError(f"Marker detection mismatch: {detected}; {stats}")
    expected, fixed_h = rectify_fixed(source, detected, OUT_W, OUT_H, method="bilinear")

    # Repeat each source sample over the exact floor-delimited HDMI bin:
    # [floor(n*display/source), floor((n+1)*display/source)).
    y_edges = np.arange(SRC_H + 1, dtype=np.int64) * 1080 // SRC_H
    x_edges = np.arange(SRC_W + 1, dtype=np.int64) * 1920 // SRC_W
    replay = np.repeat(np.repeat(source, np.diff(y_edges), axis=0), np.diff(x_edges), axis=1)
    if replay.shape != (1080, 1920, 3):
        raise RuntimeError(f"Incorrect HDMI replay dimensions: {replay.shape}")
    Image.fromarray(plane, "RGB").save(OUT / "canonical_paper_320x452.png")
    Image.fromarray(source, "RGB").save(OUT / "source_640x480.png")
    Image.fromarray(expected, "RGB").save(OUT / "expected_320x452.png")
    Image.fromarray(replay, "RGB").save(OUT / "hdmi_replay_1920x1080.png")
    write_hex(OUT / "source_640x480.hex", source)
    write_hex(OUT / "expected_320x452.hex", expected)
    metadata = {
        "source": [SRC_W, SRC_H], "output": [OUT_W, OUT_H],
        "markers_tl_tr_br_bl": detected.tolist(), "marker_size": "9x9",
        "marker_stats": stats, "algorithm": "b_rectifier bilinear fixed-point",
        "fixed_h_q16_24": fixed_h,
        "hdmi": {"size": [1920, 1080], "mapping": "repeat each source bin across [floor(n*display/source), floor((n+1)*display/source))"},
        "expected_pixels": OUT_W * OUT_H,
    }
    (OUT / "fixture_metrics.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    print(json.dumps({"output_dir": str(OUT), "detected": detected.tolist(), "expected_pixels": OUT_W * OUT_H}, indent=2))


if __name__ == "__main__":
    main()
