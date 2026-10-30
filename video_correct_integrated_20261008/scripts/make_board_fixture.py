from __future__ import annotations
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "results" / "board_fixture"
sys.path.insert(0, str(ROOT / "vendor" / "b" / "python"))
from brect.golden import detect_markers
from brect.fixed import rectify_fixed, solve_fixed, map_fixed

SRC_W, SRC_H = 320, 180
OUT_W, OUT_H = 160, 226
POINTS = [(110, 15), (235, 30), (205, 160), (100, 150)]
MARKER_RGB = [(255, 0, 0), (0, 255, 0), (255, 255, 0), (0, 0, 255)]


def to_hex(path: Path, pixels: np.ndarray) -> None:
    with path.open("w", encoding="ascii", newline="\n") as stream:
        for r, g, b in pixels.reshape(-1, 3):
            stream.write(f"{int(r):02x}{int(g):02x}{int(b):02x}\n")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGB", (SRC_W, SRC_H), (112, 112, 112))
    draw = ImageDraw.Draw(image)
    poly = POINTS
    draw.polygon(poly, fill=(226, 226, 226))

    # Restrained gray paper grid and text stay outside all chromatic marker ranges.
    for t in (0.15, 0.30, 0.45, 0.60, 0.75, 0.90):
        left = (round(POINTS[0][0] * (1-t) + POINTS[3][0] * t), round(POINTS[0][1] * (1-t) + POINTS[3][1] * t))
        right = (round(POINTS[1][0] * (1-t) + POINTS[2][0] * t), round(POINTS[1][1] * (1-t) + POINTS[2][1] * t))
        draw.line((left, right), fill=(190, 190, 190), width=1)
        top = (round(POINTS[0][0] * (1-t) + POINTS[1][0] * t), round(POINTS[0][1] * (1-t) + POINTS[1][1] * t))
        bottom = (round(POINTS[3][0] * (1-t) + POINTS[2][0] * t), round(POINTS[3][1] * (1-t) + POINTS[2][1] * t))
        draw.line((top, bottom), fill=(190, 190, 190), width=1)
    try:
        font = ImageFont.truetype("arial.ttf", 12)
    except OSError:
        font = ImageFont.load_default()
    draw.text((140, 78), "DEMO PAGE", fill=(70, 70, 70), font=font)
    draw.text((142, 96), "320 x 180", fill=(90, 90, 90), font=font)
    draw.text((142, 112), "GRAY TEXT", fill=(120, 120, 120), font=font)

    # Each saturated marker is exactly 7x7 and centered on the requested centroid.
    for (cx, cy), color in zip(POINTS, MARKER_RGB):
        draw.rectangle((cx-3, cy-3, cx+3, cy+3), fill=color)
    src = np.asarray(image, dtype=np.uint8)
    detected, stats = detect_markers(src)
    if detected is None or detected.tolist() != [list(p) for p in POINTS]:
        raise RuntimeError(f"Marker detection did not recover fixture points: {detected}, {stats}")

    expected, h = rectify_fixed(src, detected, OUT_W, OUT_H, method="bilinear")
    coefficients = solve_fixed(detected, OUT_W, OUT_H, SRC_W, SRC_H)
    valid = 0
    for y in range(OUT_H):
        for x in range(OUT_W):
            if map_fixed(coefficients, x, y)[2]:
                valid += 1

    image.save(OUT / "source_320x180.png")
    Image.fromarray(expected, "RGB").save(OUT / "expected_160x226.png")
    image.resize((SRC_W*6, SRC_H*6), Image.Resampling.NEAREST).save(OUT / "hdmi_input_1920x1080_nearest6x.png")
    to_hex(OUT / "source_320x180.hex", src)
    to_hex(OUT / "expected_160x226.hex", expected)
    (OUT / "expected_reads.txt").write_text(f"{SRC_W*SRC_H + valid*4}\n", encoding="ascii")
    metadata = {
        "source_size": [SRC_W, SRC_H], "output_size": [OUT_W, OUT_H],
        "markers_tl_tr_br_bl": [list(p) for p in POINTS],
        "marker_pixels_each": 49, "detected_markers": detected.tolist(),
        "marker_stats": stats, "method": "fixed bilinear",
        "fixed_h_q16_24": coefficients, "valid_output_pixels": valid,
        "expected_source_reads": SRC_W*SRC_H + valid*4,
        "hdmi_scale": "nearest 6x", "hdmi_size": [1920, 1080],
        "background_rgb": [112, 112, 112], "gray_only_paper_detail": True,
    }
    (OUT / "fixture_metrics.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    print(json.dumps({"output_dir": str(OUT), "detected": detected.tolist(),
                      "valid_output_pixels": valid,
                      "expected_source_reads": SRC_W*SRC_H+valid*4,
                      "fixed_h_q16_24": h}, indent=2))


if __name__ == "__main__":
    main()

