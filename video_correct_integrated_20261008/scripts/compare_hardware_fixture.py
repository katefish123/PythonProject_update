#!/usr/bin/env python3
"""Compare an HDMI capture's active window with the internal fixture image."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parents[1]
EXPECTED_PATH = (
    PROJECT_ROOT
    / "diagnostics"
    / "internal_fixture"
    / "fixture"
    / "expected_320x452.png"
)
ROI_X0, ROI_X1 = 640, 1280
ROI_Y0, ROI_Y1 = 88, 992


def load_rgb(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        return np.asarray(image.convert("RGB"), dtype=np.uint8)


def compare(actual: np.ndarray, expected: np.ndarray) -> dict:
    """Return full-resolution metrics plus a separately labeled offset diagnostic."""
    difference = np.abs(actual.astype(np.int16) - expected.astype(np.int16))
    pixel_max_difference = difference.max(axis=2)
    luminance = (
        actual[..., 0].astype(np.float32) * 0.2126
        + actual[..., 1].astype(np.float32) * 0.7152
        + actual[..., 2].astype(np.float32) * 0.0722
    )
    row_mean_luminance = luminance.mean(axis=1)

    mae = float(difference.mean())
    rmse = float(np.sqrt(np.mean(np.square(difference, dtype=np.float64))))
    flat = difference.reshape(-1)
    thresholds = {
        str(limit): float(np.mean(pixel_max_difference <= limit))
        for limit in (4, 8, 16)
    }

    # Diagnostic only: compare the capture window at integer offsets around the
    # required zero-offset result. Cropped edge pixels are excluded per candidate.
    best = None
    height, width = actual.shape[:2]
    for dy in range(-3, 4):
        for dx in range(-3, 4):
            ax0, ax1 = max(0, dx), min(width, width + dx)
            ay0, ay1 = max(0, dy), min(height, height + dy)
            ex0, ex1 = ax0 - dx, ax1 - dx
            ey0, ey1 = ay0 - dy, ay1 - dy
            delta = np.abs(
                actual[ay0:ay1, ax0:ax1].astype(np.int16)
                - expected[ey0:ey1, ex0:ex1].astype(np.int16)
            )
            candidate = (float(delta.mean()), dx, dy)
            if best is None or candidate < best:
                best = candidate

    black_rows = np.flatnonzero(row_mean_luminance <= 8.0).tolist()
    return {
        "mae_rgb": mae,
        "rmse_rgb": rmse,
        "p95_abs_rgb_error": float(np.percentile(flat, 95)),
        "p99_abs_rgb_error": float(np.percentile(flat, 99)),
        "max_abs_rgb_error": int(difference.max()),
        "pixel_max_rgb_difference_within_threshold_ratio": thresholds,
        "low_luminance_pixel_ratio_luma_le_8": float(np.mean(luminance <= 8.0)),
        "possible_black_rows_roi_relative": black_rows,
        "possible_black_row_count": len(black_rows),
        "possible_black_row_rule": "ROI row mean Rec.709 luminance <= 8 on a 0..255 scale",
        "best_offset_diagnostic": {
            "capture_window_offset_px": {"x": best[1], "y": best[2]},
            "mae_rgb": best[0],
            "search_radius_px": 3,
            "note": "Diagnostic only; edge crop varies by offset. Required zero-offset metrics remain primary.",
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Compare an HDMI capture frame with the internal fixture golden image."
    )
    parser.add_argument("capture", type=Path, help="Path to a captured HDMI frame")
    args = parser.parse_args()

    capture_path = args.capture.expanduser().resolve()
    actual_full = load_rgb(capture_path)
    expected_small = load_rgb(EXPECTED_PATH)
    actual_height, actual_width = actual_full.shape[:2]

    if expected_small.shape[:2] != (452, 320):
        raise ValueError(
            f"Expected fixture size 320x452, got "
            f"{expected_small.shape[1]}x{expected_small.shape[0]}"
        )
    if actual_width < ROI_X1 or actual_height < ROI_Y1:
        raise ValueError(
            f"Capture {actual_width}x{actual_height} is too small for the "
            f"active ROI x={ROI_X0}..{ROI_X1 - 1}, y={ROI_Y0}..{ROI_Y1 - 1}"
        )

    actual_roi = actual_full[ROI_Y0:ROI_Y1, ROI_X0:ROI_X1]
    expected_2x = np.repeat(np.repeat(expected_small, 2, axis=0), 2, axis=1)
    if actual_roi.shape != expected_2x.shape:
        raise ValueError(
            f"ROI size {actual_roi.shape[1]}x{actual_roi.shape[0]} does not match "
            f"2x fixture size {expected_2x.shape[1]}x{expected_2x.shape[0]}"
        )

    result = {
        "capture_path": str(capture_path),
        "actual_dimensions": {"width": actual_width, "height": actual_height},
        "expected_fixture_dimensions": {"width": 320, "height": 452},
        "active_roi_xy_inclusive": {
            "x": [ROI_X0, ROI_X1 - 1],
            "y": [ROI_Y0, ROI_Y1 - 1],
            "width": ROI_X1 - ROI_X0,
            "height": ROI_Y1 - ROI_Y0,
        },
        "scaling": "2x nearest-neighbor expansion of expected fixture",
        "zero_offset_metrics": compare(actual_roi, expected_2x),
        "interpretation": (
            "Report measured RGB differences. HDMI capture NV12 conversion and JPEG "
            "encoding can introduce loss; no universal pass threshold is assumed."
        ),
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
