"""Snapshot B's black-marker package and the DDR coordinate-lookahead system.

All edits and generated outputs stay in this independent directory. Existing
releases, original A/B/C sources, bitstreams and physical hardware are untouched.
"""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import re
import shutil
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

D = Path(__file__).resolve().parent
R = D.parents[1]
O = D / "results"
B = R.parent / "PythonProject_update_B/member_b_perspective_black"
BASE = R / "diagnostics/ddr_camera_coordqueue_20261013/results"
MODEL = D / "b_algorithm"
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def add_parameters(text, anchor, parameters):
    assert text.count(anchor) == 1, anchor
    return text.replace(anchor, anchor + ",\n " + parameters, 1)


def fixed_image(image, points, out_w, out_h):
    """Batch the exact B integer rules, verified against B's scalar sampler."""
    from brect.fixed import solve_fixed, map_fixed, sample_fixed
    h = solve_fixed(points, out_w, out_h, image.shape[1], image.shape[0])
    yy, xx = np.mgrid[:out_h, :out_w].astype(np.int64)
    den = h[6] * xx + h[7] * yy + h[8]
    nx = h[0] * xx + h[1] * yy + h[2]
    ny = h[3] * xx + h[4] * yy + h[5]
    assert (den > 2**20).all() and (nx >= 0).all() and (ny >= 0).all()
    qx, qy = nx * 256 // den, ny * 256 // den
    ok = (qx <= (image.shape[1] - 1) * 256) & (qy <= (image.shape[0] - 1) * 256)
    x0 = np.clip(qx >> 8, 0, image.shape[1]-1)
    y0 = np.clip(qy >> 8, 0, image.shape[0]-1)
    x1, y1 = np.minimum(x0+1, image.shape[1]-1), np.minimum(y0+1, image.shape[0]-1)
    fx, fy = (qx & 255)[..., None], (qy & 255)[..., None]
    p = image.astype(np.int64)
    top = p[y0, x0] * (256-fx) + p[y0, x1] * fx
    bot = p[y1, x0] * (256-fx) + p[y1, x1] * fx
    result = ((top * (256-fy) + bot * fy) >> 16).astype(np.uint8)
    result[~ok] = 0
    rng = np.random.default_rng(20261014)
    for index in np.r_[0, out_w-1, out_w*(out_h-1), out_w*out_h-1, rng.integers(out_w*out_h, size=500)]:
        x, y = int(index % out_w), int(index // out_w)
        sx, sy, valid = map_fixed(h, x, y)
        assert valid
        np.testing.assert_array_equal(result[y, x], sample_fixed(image, sx, sy, "bilinear"))
    return result, h


def write_hex(path, image):
    packed = (image[..., 0].astype(np.uint32) << 16) | (image[..., 1].astype(np.uint32) << 8) | image[..., 2]
    np.savetxt(path, packed.reshape(-1), fmt="%06x")


def fixture(config):
    from brect.golden import detect_markers, homography
    sw, sh = config["source"]
    ow, oh = config["output"]
    points = config["fixture_points"]
    document = Image.new("RGB", (ow, oh), "white")
    draw = ImageDraw.Draw(document)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 34)
        small = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 22)
    except OSError:
        font = small = ImageFont.load_default()
    draw.text((70, 100), "BLACK MARKER TEST", font=font, fill="black")
    draw.text((70, 154), "FPGA PERSPECTIVE CORRECTION", font=small, fill="black")
    draw.text((70, 188), "640 x 904 / RGB888", font=small, fill="black")
    for y in range(260, 780, 52):
        draw.line((90, y, 550, y), fill="#606060", width=2)
    for x in range(90, 551, 46):
        draw.line((x, 260, x, 780), fill="#808080", width=2)
    draw.ellipse((220, 400, 420, 600), outline="#303030", width=5)
    draw.rectangle((240, 630, 300, 690), fill="#d62828")
    draw.rectangle((310, 630, 370, 690), fill="#2872d6")
    inverse = homography(points, ow, oh)
    forward = np.linalg.inv(inverse)
    yy, xx = np.mgrid[:sh, :sw]
    uvw = forward @ np.stack([xx.ravel(), yy.ravel(), np.ones(xx.size)])
    u, v = uvw[:2] / uvw[2]
    inside = (u >= 0) & (u <= ow-1) & (v >= 0) & (v <= oh-1)
    pixels = np.full((sw*sh, 3), 180, np.uint8)
    paper = np.asarray(document)
    pixels[inside] = paper[np.floor(v[inside]+0.5).astype(int), np.floor(u[inside]+0.5).astype(int)]
    image = pixels.reshape(sh, sw, 3)
    radius = config["fixture_marker_radius"]
    for x, y in points:
        image[y-radius:y+radius+1, x-radius:x+radius+1] = 0
    found, stats = detect_markers(image, thresholds={"black": config["black"]}, rois=config["rois"],
                                  min_pixels=config["min_pixels"], max_pixels=config["max_pixels"], max_span=config["max_span"])
    np.testing.assert_array_equal(found, points)
    expected, h = fixed_image(image, found, ow, oh)
    Image.fromarray(image).save(O / "source_960x540.png")
    Image.fromarray(image).resize(tuple(config["input"]), Image.Resampling.NEAREST).save(O / "camera_target_1920x1080.png")
    Image.fromarray(expected).save(O / "expected_640x904.png")
    overlay = Image.fromarray(image)
    od = ImageDraw.Draw(overlay)
    for name, bounds in config["rois"].items():
        lo, hi = bounds
        od.rectangle((*lo, *hi), outline="red", width=2)
        od.text((lo[0], max(0, lo[1]-14)), name, fill="red")
    overlay.save(O / "roi_guide_960x540.png")
    preview = Image.new("RGB", (1310, 590), "#eeeeee")
    pd = ImageDraw.Draw(preview)
    pd.text((12, 10), "Synthetic input with black text / ROI guide", fill="black")
    preview.paste(overlay, (12, 38))
    pd.text((990, 10), "Expected correction", fill="black")
    preview.paste(Image.fromarray(expected).resize((300, 424)), (990, 64))
    preview.save(O / "black_correction_preview.png")
    write_hex(O / "source_960x540.hex", image)
    write_hex(O / "expected_640x904.hex", expected)
    write_json(O / "fixture.json", {"synthetic": True, "source": [sw, sh], "output": [ow, oh],
                                    "points": points, "H_q": h, "statistics": stats,
                                    "scalar_fixed_checks": 504, "real_camera_accepted": False})


def main():
    O.mkdir(exist_ok=True)
    config = json.loads((D / "config.json").read_text(encoding="utf-8"))
    # This release preserves the qualified video geometry and marker statistics.
    # Do not silently accept configuration values that the board top does not use.
    assert config["input"] == [1920, 1080] and config["source"] == [960, 540] and config["output"] == [640, 904]
    assert (config["min_pixels"], config["max_pixels"], config["max_span"]) == (16, 4096, 128)
    # Copy B's package once. Original extracted contents and the Git checkout stay intact.
    if not MODEL.exists():
        shutil.copytree(B, MODEL, ignore=shutil.ignore_patterns("work", "backups", ".DS_Store", "__pycache__"))
    sys.path.insert(0, str(MODEL / "python"))
    from brect.golden import marker_rois
    marker_rois(*config["source"], config["rois"])
    # Pango ADS requires the index to have its actual 0..7 width. This is the
    # same synthesis adaptation previously applied to the qualified color detector.
    marker = MODEL / "rtl/marker_detector.v"
    text = (B / "rtl/marker_detector.v").read_text(encoding="utf-8-sig")
    text = text.replace("integer i,component,k,j;", "integer i,k,j;\n reg [2:0] component;")
    text = text.replace("component%2==0", "component[0]==1'b0").replace("component/2", "component[2:1]")
    marker.write_text(text, encoding="utf-8")
    params = ["BLACK_RMIN", "BLACK_RMAX", "BLACK_GMIN", "BLACK_GMAX", "BLACK_BMIN", "BLACK_BMAX"]
    defaults = [0, 64, 0, 64, 0, 64]
    roi_defaults = ["0", "SRC_W/2-1", "0", "SRC_H/2-1", "SRC_W/2", "SRC_W-1", "0", "SRC_H/2-1",
                    "SRC_W/2", "SRC_W-1", "SRC_H/2", "SRC_H-1", "0", "SRC_W/2-1", "SRC_H/2", "SRC_H-1"]
    for corner in range(4):
        params += [f"P{corner}_{axis}" for axis in ("XMIN", "XMAX", "YMIN", "YMAX")]
    defaults += roi_defaults
    declaration = "parameter " + ",".join(f"{p}={v}" for p, v in zip(params, defaults))
    forwarding = ",\n  " + ",".join(f".{p}({p})" for p in params)
    flow = (BASE / "build.tcl").read_text(encoding="utf-8-sig")
    originals = [Path(m[1]) for line in flow.splitlines() if (m := re.fullmatch(r"add_design \{(.+)\}", line))]
    baseline = json.loads((R / "release/ddr_camera_coordqueue_20261013/source_hashes.json").read_text(encoding="utf-8-sig"))
    for path, digest in baseline.items():
        assert sha(Path(path)) == digest, f"Baseline source changed: {path}"
    replacements = {}
    for original in originals:
        if original.parent == R / "vendor/b/rtl" or original == R / "rtl/algo/marker_detector.v":
            target = MODEL / "rtl" / original.name
        else:
            target = D / "src" / original.relative_to(R)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(original, target)
        replacements[original.as_posix()] = target.as_posix()
    processor = Path(replacements[(BASE / "frame_processor.v").as_posix()])
    s = processor.read_text(encoding="utf-8-sig")
    s = add_parameters(s, "parameter TIMEOUT_CYCLES=1000000,COORD_QUEUE_BITS=4", declaration)
    anchor = ".MAX_PIXELS(MAX_PIXELS),.MAX_SPAN(MAX_SPAN)) algorithm("
    assert s.count(anchor) == 1
    s = s.replace(anchor, ".MAX_PIXELS(MAX_PIXELS),.MAX_SPAN(MAX_SPAN)" + forwarding + ") algorithm(")
    processor.write_text(s, encoding="utf-8")
    core = Path(replacements[(R / "rtl/top/video_correct_ddr_core.v").as_posix()])
    s = core.read_text(encoding="utf-8-sig")
    s = add_parameters(s, "parameter FIFO_ADDR_BITS=9,BIST_BEATS=256", declaration)
    anchor = ".OUT_W(OUT_W),.OUT_H(OUT_H)) processor("
    assert s.count(anchor) == 1
    s = s.replace(anchor, ".OUT_W(OUT_W),.OUT_H(OUT_H)" + forwarding + ") processor(")
    core.write_text(s, encoding="utf-8")
    top_original = R / "diagnostics/ddr_camera_hires_rowtrain_20261013/results/video_correct_ddr_top.v"
    top = Path(replacements[top_original.as_posix()])
    prod_values = [v for channel in zip(config["black"][0], config["black"][1]) for v in channel]
    for bounds in config["rois"].values():
        lo, hi = bounds
        prod_values += [lo[0], hi[0], lo[1], hi[1]]
    s = top.read_text(encoding="utf-8-sig")
    decl = "parameter " + ",".join(f"{p}={v}" for p, v in zip(params, prod_values))
    s = s.replace("module video_correct_ddr_top(", "module video_correct_ddr_top #(\n " + decl + "\n)(", 1)
    s = s.replace(".SCALE(1),.FIFO_ADDR_BITS(10)) core(", ".SCALE(1),.FIFO_ADDR_BITS(10)" + forwarding + ") core(", 1)
    top.write_text(s, encoding="utf-8")
    constraints = D / "src/constr/board_ddr.fdc"
    constraints.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(R / "constr/board_ddr.fdc", constraints)
    replacements[(R / "constr/board_ddr.fdc").as_posix()] = constraints.as_posix()
    # Remap every source, including different copied testbench locations, to this snapshot.
    replacements[(R / "vendor/b/vectors").as_posix()] = (MODEL / "vectors").as_posix()
    replacements[BASE.as_posix()] = O.as_posix()
    replacements[(BASE.parent).as_posix()] = O.as_posix()
    for original, target in sorted(replacements.items(), key=lambda pair: -len(pair[0])):
        flow = flow.replace(original, target)
    (O / "build.tcl").write_text(flow, encoding="utf-8")
    tests = json.loads((BASE / "simulation_cases.json").read_text(encoding="utf-8-sig"))
    tests.pop("tb_old_contention_control")  # legacy failure-control image is not this release
    for file in list(BASE.glob("tb*.sv")) + list(BASE.glob("tb*.do")) + list(BASE.parent.glob("tb*.sv")):
        s = file.read_text(encoding="utf-8-sig")
        for original, target in sorted(replacements.items(), key=lambda pair: -len(pair[0])):
            s = s.replace(original, target)
        if file.name == "tb_ddr_full_frame.sv":
            values = ",".join(f".{p}({v})" for p, v in zip(params, prod_values))
            s = s.replace(".TIMEOUT_CYCLES(12000000)) dut(", ".TIMEOUT_CYCLES(12000000)," + values + ") dut(")
        (O / file.name).write_text(s, encoding="utf-8")
    write_json(O / "simulation_cases.json", tests)
    fixture(config)
    paths = [Path(m[1]) for line in flow.splitlines() if (m := re.fullmatch(r"add_design \{(.+)\}", line))] + [constraints]
    write_json(O / "source_hashes.json", {str(p): sha(p) for p in paths})
    write_json(O / "configuration.json", {**config, "marker_mode": "black_rgb_with_spatial_rois", "processing_clock_mhz": 27,
               "coordinate_lookahead_credits": 16, "display_row_train": True, "physical_acceptance": False,
               "upstream_repository": "https://github.com/katefish123/PythonProject_update", "upstream_branch": "main-B",
               "upstream_commit": "4106f3babb65096927d365bbab55f070b90325e2",
               "upstream_zip_sha256": sha(B.parent / "member_b_perspective_black.zip"),
               "prepared_at_utc": datetime.now(timezone.utc).isoformat(), "baseline_release": "ddr_camera_coordqueue_20261013",
               "limitations": ["Fixed ROI centroids do not support free 360-degree tracking", "30/60fps processing not verified",
                               "Lens distortion calibration is not included", "New camera and hardware validation required"]})
    print(f"BLACK_DDR_PREPARED {len(paths)} source/constraint files in {D}")


if __name__ == "__main__":
    main()
