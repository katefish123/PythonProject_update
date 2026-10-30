from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent / "fixture"
sys.path.insert(0, str(ROOT / "vendor" / "b" / "python"))
from brect.fixed import rectify_fixed
from brect.golden import detect_markers

SRC_W, SRC_H = 640, 480
OUT_W, OUT_H = 320, 452
POINTS = [(100, 60), (540, 90), (570, 420), (70, 390)]
COLORS = [(255, 0, 0), (0, 255, 0), (255, 255, 0), (0, 0, 255)]


def source_pixel(x: np.ndarray, y: np.ndarray) -> np.ndarray:
    shade = np.where((((x >> 5) ^ (y >> 5)) & 1) != 0, 200, 152).astype(np.uint8)
    image = np.repeat(shade[..., None], 3, axis=-1)
    boxes = [(96, 56, 103, 63), (536, 86, 543, 93), (566, 416, 573, 423), (66, 386, 73, 393)]
    for (x0, y0, x1, y1), color in zip(boxes, COLORS):
        mask = (x >= x0) & (x <= x1) & (y >= y0) & (y <= y1)
        image[mask] = color
    return image


def write_hex(path: Path, image: np.ndarray) -> None:
    with path.open("w", encoding="ascii", newline="\n") as f:
        for r, g, b in image.reshape(-1, 3):
            f.write(f"{int(r):02x}{int(g):02x}{int(b):02x}\n")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    yy, xx = np.mgrid[0:SRC_H, 0:SRC_W]
    source = source_pixel(xx, yy)
    detected, stats = detect_markers(source)
    if detected is None or detected.tolist() != [list(p) for p in POINTS]:
        raise RuntimeError(f"Marker detector mismatch: {detected}; expected={POINTS}; stats={stats}")
    # The RTL centroid rounds via (sum + count/2) / count. These asymmetric
    # 8x8 integer boxes have exactly integral rounded centroids at POINTS.
    for (cx, cy), st in zip(POINTS, stats.values()):
        if st["count"] != 64 or st["span"] != (7, 7):
            raise RuntimeError(f"Unexpected marker component for {(cx, cy)}: {st}")

    expected, fixed_h = rectify_fixed(source, detected, OUT_W, OUT_H, method="bilinear")
    # Input pixel ix,iy is source(floor(ix/3), ceil(iy*4/9)); clamp only the
    # two unsampled last raster rows where ceil() equals 480.
    ry, rx = np.mgrid[0:1080, 0:1920]
    sy = np.minimum((ry * 4 + 8) // 9, SRC_H - 1)
    sx = rx // 3
    hdmi = source[sy, sx]
    # HDMI active-area preview: center the result at native 2x scale (640x904).
    window = np.zeros((1080, 1920, 3), dtype=np.uint8)
    expanded = np.repeat(np.repeat(expected, 2, axis=0), 2, axis=1)
    wx, wy = (1920 - 640) // 2, (1080 - 904) // 2
    window[wy:wy + 904, wx:wx + 640] = expanded

    Image.fromarray(source).save(OUT / "source_640x480.png")
    Image.fromarray(expected).save(OUT / "expected_320x452.png")
    Image.fromarray(hdmi).save(OUT / "input_raster_1920x1080.png")
    Image.fromarray(window).save(OUT / "expected_hdmi_window_1920x1080.png")
    write_hex(OUT / "source_640x480.hex", source)
    write_hex(OUT / "expected_320x452.hex", expected)
    meta = {
        "source_size": [SRC_W, SRC_H], "input_raster": [1920, 1080],
        "output_size": [OUT_W, OUT_H], "markers_tl_tr_br_bl": detected.tolist(),
        "marker_size": "8x8", "marker_boxes_inclusive": [[96,56,103,63],[536,86,543,93],[566,416,573,423],[66,386,73,393]],
        "centroid_rule": "RTL round-half-up: (sum + count/2) / count; 8x8 boxes chosen to round exactly to the stated integer centers",
        "marker_stats": stats, "algorithm_oracle": "vendor/b/python/brect.fixed.rectify_fixed bilinear",
        "fixed_h_q16_24": fixed_h,
        "input_mapping": {"x": "ix//3", "y": "ceil(iy*4/9), clipped to 479 on the two unsampled terminal rows"},
        "display_window_active_relative": [640, 88, 1280, 992],
        "expected_pixel_count": OUT_W * OUT_H,
    }
    (OUT / "fixture_metrics.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    print(json.dumps({"output": str(OUT), "detected": detected.tolist(), "expected_pixels": OUT_W * OUT_H}, indent=2))


if __name__ == "__main__":
    main()
