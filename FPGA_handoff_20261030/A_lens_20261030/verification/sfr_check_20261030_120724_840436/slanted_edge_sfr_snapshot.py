"""Conservative straight slanted-edge SFR estimator; no ISO certification claim.

PNG code values are never assumed linear: the caller must supply transfer.
ROI is (x, y, width, height), with no implicit clipping or target detection.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

import cv2
import numpy as np

METHOD_VERSION = "straight-edge-normal-binning-4x-v1"


class SfrError(ValueError):
    def __init__(self, code: str, message: str, **diagnostics):
        super().__init__(message)
        self.code = code
        self.diagnostics = diagnostics


def _require(condition, code, message, **diagnostics):
    if not condition:
        raise SfrError(code, message, **diagnostics)


def linearize(code_values: np.ndarray, transfer: str) -> np.ndarray:
    """Decode explicitly selected transfer, independently in each RGB channel."""
    _require(transfer in {"linear", "srgb"}, "transfer", "Choose linear or srgb explicitly.")
    values = np.asarray(code_values, dtype=np.float64)
    _require(np.isfinite(values).all() and values.min() >= 0 and values.max() <= 1,
             "range", "Code values must be finite and within [0,1].")
    if transfer == "srgb":
        values = np.where(values <= 0.04045, values / 12.92,
                          ((values + 0.055) / 1.055) ** 2.4)
    return values


def _estimate(luma: np.ndarray, orientation: str) -> dict:
    _require(orientation in {"vertical", "horizontal"}, "orientation",
             "Choose vertical or horizontal edge direction explicitly.")
    # In this coordinate system each row crosses a nearly vertical edge.
    image = luma if orientation == "vertical" else luma.T
    rows, columns = image.shape
    _require(rows >= 64 and columns >= 64, "roi_size", "ROI must span at least 64x64 pixels.")
    border = max(8, columns // 10)
    left = np.median(image[:, :border], axis=1)
    right = np.median(image[:, -border:], axis=1)
    contrast = float(np.median(right - left))
    _require(abs(contrast) >= 0.10, "contrast", "ROI lacks one sufficiently strong edge.",
             absolute_linear_contrast=abs(contrast))
    sign = 1 if contrast > 0 else -1
    _require(np.mean(sign * (right - left) > 0.08) >= 0.95, "edge_polarity",
             "Edge polarity is inconsistent across rows; avoid corners or multiple features.")

    # Smoothing is for edge location only. ESF below uses original linear pixels.
    smooth = image.copy()
    kernel = np.array([1, 4, 6, 4, 1], dtype=float) / 16
    for row in range(rows):
        smooth[row] = np.convolve(np.pad(image[row], 2, mode="edge"), kernel, mode="valid")
    gradient = sign * (smooth[:, 2:] - smooth[:, :-2]) / 2
    locations = []
    bad_rows = 0
    x_gradient = np.arange(1, columns - 1, dtype=float)
    for g in gradient:
        positive = np.maximum(g, 0)
        negative = np.maximum(-g, 0)
        peak = int(np.argmax(positive))
        peak_value = float(positive[peak])
        _require(peak_value > 0, "edge_location", "No edge gradient found.")
        significant = np.flatnonzero(positive >= 0.20 * peak_value)
        groups = 1 + int(np.count_nonzero(np.diff(significant) > 3))
        if negative.sum() > 0.10 * positive.sum() or groups != 1:
            bad_rows += 1
        support = np.abs(x_gradient - x_gradient[peak]) <= max(12, columns // 8)
        weight = positive * support
        locations.append(float(np.dot(x_gradient, weight) / weight.sum()))
    _require(bad_rows <= int(0.05 * rows), "multiple_edges",
             "ROI contains extra edges, texture, or excessive row noise.", bad_rows=bad_rows)

    y = np.arange(rows, dtype=float)
    positions = np.asarray(locations)
    slope, intercept = np.linalg.lstsq(np.column_stack((y, np.ones(rows))), positions, rcond=None)[0]
    residual = positions - (slope * y + intercept)
    rms = float(np.sqrt(np.mean(residual ** 2)))
    maximum = float(np.max(np.abs(residual)))
    angle = math.degrees(math.atan(abs(float(slope))))
    _require(2 <= angle <= 12, "edge_angle",
             "Use an edge slanted 2 to 12 degrees from the selected axis.", angle_degrees=angle)
    _require(rms <= 0.25 and maximum <= 0.75, "edge_straightness",
             "Edge is curved, ragged, interrupted, or poorly located.", rms_pixels=rms, maximum_pixels=maximum)
    fitted = slope * y + intercept
    margin = float(min(fitted.min(), (columns - 1 - fitted).min()))
    _require(margin >= 24, "edge_margin", "Edge is too close to an ROI boundary.", margin_pixels=margin)
    normal_scale = math.sqrt(1 + slope ** 2)
    distance = (np.arange(columns)[None, :] - fitted[:, None]) / normal_scale
    # Side plateaus must be quiet; do not silently average texture into an ESF.
    side_spread = []
    for side in [distance < -16, distance > 16]:
        values = image[side]
        median = float(np.median(values))
        side_spread.append(float(1.4826 * np.median(np.abs(values - median))))
    noise_ratio = max(side_spread) / abs(contrast)
    _require(noise_ratio <= 0.02, "plateau_noise",
             "Plateau noise or shading exceeds 2% of edge contrast.", relative_noise=noise_ratio)

    delta = 0.25  # pixels, measured NORMAL to the fitted edge
    radius = min(64, math.floor(margin / normal_scale) - 2)
    half_bins = radius * 4
    bins = np.floor(distance / delta + 0.5).astype(np.int64)
    selected = np.abs(bins) <= half_bins
    selected_bins = bins[selected] + half_bins
    counts = np.bincount(selected_bins, minlength=2 * half_bins + 1)
    _require(counts.min() >= 8 and counts.max() / counts.min() <= 8,
             "phase_coverage", "Insufficient or uneven subpixel-phase coverage; choose a taller/differently slanted ROI.",
             minimum_bin_samples=int(counts.min()), maximum_bin_samples=int(counts.max()))
    sums = np.bincount(selected_bins, weights=image[selected], minlength=len(counts))
    esf = sums / counts
    esf = (esf - float(np.median(left))) / contrast
    coordinate = np.arange(-half_bins, half_bins + 1, dtype=float) * delta
    # Central difference approximates the derivative at sample n.
    lsf = np.zeros_like(esf)
    lsf[1:-1] = (esf[2:] - esf[:-2]) / (2 * delta)
    negative_lsf = float(np.maximum(-lsf, 0).sum() / max(np.maximum(lsf, 0).sum(), 1e-12))
    _require(negative_lsf <= 0.10, "esf_shape", "ESF is too nonmonotonic for this conservative estimator.", negative_lsf_fraction=negative_lsf)
    window = 0.54 + 0.46 * np.cos(np.pi * coordinate / radius)
    windowed = lsf * window
    nfft = 1 << math.ceil(math.log2(max(4096, 8 * len(lsf))))
    frequency = np.fft.rfftfreq(nfft, d=delta)
    amplitude = np.abs(np.fft.rfft(windowed, n=nfft))
    _require(amplitude[0] > 1e-8, "zero_dc", "Derivative has no reliable DC normalization.")
    band = frequency <= 0.5
    frequency = frequency[band]
    sfr = amplitude[band] / amplitude[0]
    argument = 2 * np.pi * delta * frequency
    correction = np.ones_like(argument)
    correction[1:] = argument[1:] / np.sin(argument[1:])
    sfr *= correction
    _require(np.isfinite(sfr).all(), "spectrum", "Invalid frequency response.")
    _require(float(sfr.max()) <= 1.25, "sfr_peak", "Strong sharpening/ringing makes this result unsuitable for the conservative estimate.")
    crossing = np.flatnonzero((sfr[:-1] >= 0.5) & (sfr[1:] < 0.5))
    _require(len(crossing) == 1, "mtf50_crossing",
             "Exactly one reliable 50% crossing is required within 0 to 0.5 cycles/pixel.", crossing_count=len(crossing))
    i = int(crossing[0])
    mtf50 = float(frequency[i] + (0.5 - sfr[i]) * (frequency[i + 1] - frequency[i]) / (sfr[i + 1] - sfr[i]))
    return {
        "accepted": True, "method": METHOD_VERSION, "iso_certified": False,
        "orientation": orientation, "oversampling": 4,
        "mtf50_cycles_per_pixel": mtf50, "frequency_units": "cycles per input-image pixel, normal to edge",
        "frequency_limit_cycles_per_pixel": 0.5,
        "quality": {"linear_contrast": abs(contrast), "polarity": "rising" if sign > 0 else "falling",
                    "edge_slope": float(slope), "edge_intercept_roi_pixels": float(intercept),
                    "edge_angle_degrees_from_selected_axis": angle,
                    "fit_rms_pixels": rms, "fit_maximum_pixels": maximum, "edge_margin_pixels": margin,
                    "plateau_relative_noise": noise_ratio, "negative_lsf_fraction": negative_lsf,
                    "minimum_bin_samples": int(counts.min()), "maximum_bin_samples": int(counts.max())},
        "frequency_cycles_per_pixel": frequency.tolist(), "sfr_dc_normalized": sfr.tolist(),
        "esf_position_normal_pixels": coordinate.tolist(), "esf_normalized": esf.tolist(),
        "lsf": lsf.tolist(), "window": "Hamming centered on fitted edge",
        "lsf_windowed": windowed.tolist(), "derivative_correction": correction.tolist(),
    }


def analyze_png(path: str | Path, roi, *, orientation: str, transfer: str) -> dict:
    """Return measured SFR or raise SfrError; never invent a value on rejection."""
    path = Path(path).resolve()
    _require(transfer in {"linear", "srgb"}, "transfer", "Select transfer=linear or transfer=srgb.")
    _require(orientation in {"vertical", "horizontal"}, "orientation", "Select vertical or horizontal edge direction.")
    _require(path.is_file(), "input_file", "PNG input file does not exist.")
    payload = path.read_bytes()
    _require(payload[:8] == b"\x89PNG\r\n\x1a\n", "input_format", "Only PNG inputs are supported.")
    image = cv2.imdecode(np.frombuffer(payload, dtype=np.uint8), cv2.IMREAD_UNCHANGED)
    _require(image is not None, "decode", "PNG could not be decoded.")
    _require(image.dtype in {np.dtype('uint8'), np.dtype('uint16')}, "bit_depth", "Use an 8- or 16-bit PNG.")
    _require(len(roi) == 4 and all(isinstance(v, (int, np.integer)) and not isinstance(v, bool) for v in roi),
             "roi", "ROI must contain four integer values: x y width height.")
    x, y, width, height = map(int, roi)
    _require(x >= 0 and y >= 0 and width > 0 and height > 0 and x + width <= image.shape[1] and y + height <= image.shape[0],
             "roi", "ROI must be positive and entirely inside the image; it is never clipped.")
    image = image[y:y + height, x:x + width]
    maximum = float(np.iinfo(image.dtype).max)
    if image.ndim == 3 and image.shape[2] == 4:
        _require(np.all(image[:, :, 3] == maximum), "alpha", "ROI must be fully opaque.")
        image = image[:, :, :3]
    _require(image.ndim == 2 or (image.ndim == 3 and image.shape[2] == 3), "channels", "Use grayscale, RGB, or fully opaque RGBA PNG.")
    codes = image.astype(float) / maximum
    clipped = float(np.mean((codes <= 0) | (codes >= 1)))
    _require(clipped <= 0.005, "clipping", "More than 0.5% of ROI code values are clipped at an endpoint.", clipped_fraction=clipped)
    decoded = linearize(codes, transfer)
    luma = decoded if decoded.ndim == 2 else decoded @ np.array([0.0722, 0.7152, 0.2126])
    result = _estimate(luma, orientation)
    result.update(input_file=str(path), input_sha256=hashlib.sha256(payload).hexdigest(),
                  roi_xywh=[x, y, width, height], input_transfer=transfer,
                  input_bit_depth=int(math.log2(maximum + 1)), input_clipped_fraction=clipped,
                  color_assumption="sRGB/Rec.709 primaries; decode RGB separately then form linear luminance; PNG ICC/gamma metadata not applied")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('png', type=Path)
    parser.add_argument('--roi', type=int, nargs=4, required=True, metavar=('X', 'Y', 'WIDTH', 'HEIGHT'))
    parser.add_argument('--orientation', choices=['vertical', 'horizontal'], required=True)
    parser.add_argument('--transfer', choices=['linear', 'srgb'], required=True)
    parser.add_argument('--output', type=Path, help='JSON result; stdout if omitted')
    args = parser.parse_args()
    try:
        result = analyze_png(args.png, args.roi, orientation=args.orientation, transfer=args.transfer)
        status = 0
    except SfrError as error:
        result = {"accepted": False, "error_code": error.code, "reason": str(error), "diagnostics": error.diagnostics,
                  "input_file": str(args.png.resolve()), "roi_xywh": args.roi,
                  "input_transfer": args.transfer, "orientation": args.orientation, "iso_certified": False}
        status = 2
    encoded = json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False)
    if args.output:
        args.output.write_text(encoded + '\n', encoding='utf-8')
    else:
        print(encoded)
    raise SystemExit(status)


if __name__ == '__main__':
    main()
