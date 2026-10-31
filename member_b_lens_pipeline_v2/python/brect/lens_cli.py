"""Marker-free calibrated lens correction and explicit homography CLI."""
import argparse
import json
from pathlib import Path
import numpy as np
from PIL import Image
from .calibration import load_calibration
from .lens import map_lens_float, render_lens_float, render_lens_fixed
from .fixed import map_fixed
from .lens import _homography_fixed, _map_hardware
from .viewport import plan_viewport, mapping_mask, read_homography as _read_homography


def _map_statistics(profile, h, output_size):
    width, height = output_size
    hh = _homography_fixed(h)
    hardware = profile.to_hardware()
    errors, rejected = [], 0
    for y in np.unique(np.linspace(0, height - 1, min(height, 61)).astype(int)):
        for x in np.unique(np.linspace(0, width - 1, min(width, 101)).astype(int)):
            x, y = int(x), int(y)
            den = float(h[2] @ [x, y, 1.])
            u, v, hvalid = map_fixed(hh, x, y)
            if den <= 1. / 16. or not np.isfinite(den) or not hvalid:
                rejected += 1
                continue
            uf, vf = float(h[0] @ [x, y, 1.]) / den, float(h[1] @ [x, y, 1.]) / den
            sx, sy, valid = map_lens_float(profile, uf, vf)
            qx, qy, qvalid = _map_hardware(hardware, u, v)
            if not (valid and qvalid):
                rejected += 1
                continue
            errors.append([sx - qx / 256., sy - qy / 256.])
    if not errors:
        return {"compared_points": 0, "rejected_points": rejected, "note": "No numerically valid comparison points"}
    error = np.asarray(errors)
    return {"compared_points": len(errors), "rejected_points": rejected,
            "max_axis_error_px": float(np.max(np.abs(error))),
            "max_euclidean_error_px": float(np.max(np.linalg.norm(error, axis=1))),
            "rms_euclidean_error_px": float(np.sqrt(np.mean(np.sum(error * error, axis=1)))),
            "note": "Software float versus quantized combined H+lens source mapping; not optical calibration accuracy"}


def _pixel_difference(first, second):
    maximum, total = 0, 0
    for row in range(0, first.shape[0], 64):
        difference = np.abs(first[row:row + 64].astype(np.int16) - second[row:row + 64].astype(np.int16))
        maximum = max(maximum, int(difference.max()))
        total += int(difference.sum(dtype=np.int64))
    return {"max_channel_difference": maximum,
            "mean_absolute_channel_difference": total / first.size}


def main(argv=None):
    parser = argparse.ArgumentParser(description="相机标定参数 → 镜头校正；可显式组合目标到理想源图的 H，无标记检测")
    parser.add_argument("input", help="Source RGB image, in the calibration's exact pixel grid")
    parser.add_argument("--calibration", required=True, help="Nested model/video calibration JSON")
    parser.add_argument("--homography", "--H", help="JSON file: 3 by 3 destination-to-ideal-source H, or {\"H\": [...]} (default identity)")
    parser.add_argument("--size", "--output-size", nargs=2, type=int, metavar=("WIDTH", "HEIGHT"), help="Output dimensions; default calibration width/height")
    parser.add_argument("--method", choices=("bilinear", "nearest"), default="bilinear")
    parser.add_argument("--mode", choices=("both", "float", "fixed"), default="both")
    parser.add_argument("--border", choices=("auto", "keep"), default="auto",
                        help="auto: verified crop/zoom without missing source pixels; keep: preserve the requested field of view, allowing black borders")
    parser.add_argument("--output", default="results/lens", help="Output directory")
    args = parser.parse_args(argv)
    try:
        with Image.open(args.input) as source:
            # Do not auto-rotate EXIF or silently resize: the calibration refers
            # to the stored decoded raster pixel grid.
            image = np.array(source.convert("RGB"))
        profile = load_calibration(args.calibration, (image.shape[1], image.shape[0]))
        h = _read_homography(args.homography)
        size = tuple(args.size) if args.size else (profile.width, profile.height)
        base_h = h.copy()
        if args.border == "auto":
            h, framing = plan_viewport(profile, H=h, output_size=size)
        else:
            framing = {"policy": "keep", "after": {
                "float_outside_pixels": int((~mapping_mask(profile,h,size)).sum()),
                "fixed_outside_pixels": int((~mapping_mask(profile,h,size,fixed=True)).sum())}}
        outputs = {}
        if args.mode in ("float", "both"):
            outputs["float"] = render_lens_float(image, profile, H=h, output_size=size, method=args.method)
        if args.mode in ("fixed", "both"):
            outputs["fixed"] = render_lens_fixed(image, profile, H=h, output_size=size, method=args.method)
        info = {"input_name": Path(args.input).name, "source_size": [profile.width, profile.height],
                "output_size": list(size), "destination_to_ideal_source_H": h.tolist(),
                "requested_destination_to_ideal_source_H": base_h.tolist(),
                "border_policy": args.border, "framing": framing,
                "method": args.method, "mode": args.mode,
                "sampling": "H then Brown lens mapping; sample original RGB source once",
                "marker_detection": False, "calibration_metadata": profile.metadata,
                "hardware_parameters": profile.to_hardware(),
                "mapping_comparison": _map_statistics(profile, h, size)}
        if len(outputs) == 2:
            info["output_pixel_difference"] = _pixel_difference(outputs["float"], outputs["fixed"])
        destination = Path(args.output)
        destination.mkdir(parents=True, exist_ok=True)
        for name, result in outputs.items():
            Image.fromarray(result).save(destination / f"{name}.png")
        (destination / "parameters.json").write_text(json.dumps(info, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"Saved {destination}: {', '.join(outputs)}; source {profile.width}x{profile.height}; deployment metadata retained")
    except (OSError, ValueError, TypeError) as error:
        parser.exit(2, f"lens_cli: {error}\n")


if __name__ == "__main__":
    main()
