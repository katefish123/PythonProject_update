"""Check a saved camera RGB image with exactly the compiled black ROI rules."""
from pathlib import Path
import argparse
import json
import sys
import numpy as np
from PIL import Image, ImageDraw

D = Path(__file__).resolve().parent
sys.path.insert(0, str(D / "b_algorithm/python"))
from brect.golden import detect_markers
from prepare import fixed_image


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image", type=Path)
    ap.add_argument("--output", type=Path, default=D / "results/camera_image_check")
    args = ap.parse_args()
    config = json.loads((D / "config.json").read_text(encoding="utf-8"))
    rgb = np.asarray(Image.open(args.image).convert("RGB"))
    sw, sh = config["source"]
    if rgb.shape[:2] == tuple(config["input"][::-1]):
        # Mirrors the FPGA capture coordinates; do not filter before detection.
        ys = np.arange(sh) * rgb.shape[0] // sh
        xs = np.arange(sw) * rgb.shape[1] // sw
        rgb = rgb[ys[:, None], xs]
    elif rgb.shape[:2] != (sh, sw):
        raise ValueError(f"Expected {config['input']} camera frame or {config['source']} sampled frame")
    points, stats = detect_markers(rgb, thresholds={"black": config["black"]}, rois=config["rois"],
        min_pixels=config["min_pixels"], max_pixels=config["max_pixels"], max_span=config["max_span"])
    args.output.mkdir(parents=True, exist_ok=True)
    overlay = Image.fromarray(rgb)
    draw = ImageDraw.Draw(overlay)
    for name, (lo, hi) in config["rois"].items():
        draw.rectangle((*lo, *hi), outline="red", width=2)
        draw.text((lo[0], max(0, lo[1]-14)), name, fill="red")
    overlay.save(args.output / "roi_check.png")
    result = {"input": str(args.image.resolve()), "marker_detected": points is not None,
              "statistics": stats, "points": None if points is None else points.tolist(),
              "software_check_only": True}
    if points is not None:
        try:
            image, h = fixed_image(rgb, points, *config["output"])
            Image.fromarray(image).save(args.output / "corrected.png")
            result.update(geometry_accepted=True, H_q=h)
        except ValueError as error:
            result.update(geometry_accepted=False, reason=str(error))
    (args.output / "measurement.json").write_text(json.dumps(result, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if not result.get("geometry_accepted", False):
        raise SystemExit(2)


if __name__ == "__main__":
    main()
