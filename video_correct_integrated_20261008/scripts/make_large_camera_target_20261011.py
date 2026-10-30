"""Create a separate optical test target; never change the original fixture/viewer."""
from pathlib import Path
import hashlib
import json
import sys
import numpy as np
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
original = root / "results/ddr_fixture/source_640x480.png"
original_sha = hashlib.sha256(original.read_bytes()).hexdigest()
out = root / "results/camera_target_large_20261011"
out.mkdir(exist_ok=True)
image = Image.open(original).convert("RGB")
points = [(200, 45), (465, 100), (435, 420), (180, 390)]
colours = [(255, 0, 0), (0, 255, 0), (255, 255, 0), (0, 0, 255)]
draw = ImageDraw.Draw(image)
for (x, y), colour in zip(points, colours):
    draw.rectangle((x - 13, y - 13, x + 13, y + 13), fill=colour)
target = out / "source_large_markers_640x480.png"
image.save(target)
sys.path.insert(0, str(root / "vendor/b/python"))
from brect.golden import detect_markers
detected, stats = detect_markers(np.asarray(image))
assert np.array_equal(detected, points), detected
assert all(s["count"] == 729 for s in stats.values()), stats
viewer_source = root / "scripts/show_camera_target.py"
viewer = viewer_source.read_text(encoding="utf-8-sig")
old_asset = "results/ddr_fixture/source_640x480.png"
assert viewer.count(old_asset) == 1
viewer = viewer.replace(old_asset, "results/camera_target_large_20261011/source_large_markers_640x480.png")
viewer = viewer.replace("相机测试图片（静态）", "相机测试图片（大角标、静态）")
(root / "scripts/show_camera_target_large.py").write_text(viewer, encoding="utf-8")
entry = (root / "显示相机测试图.cmd").read_bytes()
assert entry.count(b"show_camera_target.py") == 1
(root / "显示相机测试图_大角标.cmd").write_bytes(entry.replace(b"show_camera_target.py", b"show_camera_target_large.py"))
assert hashlib.sha256(original.read_bytes()).hexdigest() == original_sha
record = {"source_size": [640, 480], "marker_side": 27, "original_marker_side": 9,
    "points": points, "golden_marker_stats": stats, "centres_unchanged": True,
    "original_asset_sha256": original_sha, "new_asset_sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
    "original_asset_modified": False, "original_viewer_modified": False,
    "purpose": "Independent physical-camera target with larger colour patches, to reduce optical edge blending and provide sufficient actual sampled marker area. Not FPGA output or hardware acceptance.",
    "entry": "显示相机测试图_大角标.cmd", "esc_closes_viewer": True}
(out / "target.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"asset": str(target), "centres": detected.tolist(), "stats": stats}, ensure_ascii=False, indent=2))
