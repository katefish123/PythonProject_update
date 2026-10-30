"""Check photographed four-marker input in a real OBS recording."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import shutil
import subprocess
import sys
import numpy as np

root = Path(__file__).resolve().parents[1]
hardware = root / "results/hardware_20261009"
sys.path.insert(0, str(root / "vendor/b/python"))
from brect.golden import DEFAULT_THRESHOLDS, detect_markers
ffmpeg = root / "tools/python_packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe"
original = Path("C:/Users/夏菲/Videos/2026-10-11 12-09-34.mp4")
video = hardware / "native_target_input_20261011_120934.mp4"
shutil.copyfile(original, video)
process = subprocess.run([str(ffmpeg), "-hide_banner", "-loglevel", "error", "-i", str(video),
    "-an", "-vf", "fps=1,scale=640:480:flags=neighbor", "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1"], capture_output=True, check=False)
assert process.returncode == 0, process.stderr.decode("utf-8", errors="replace")
assert len(process.stdout) % (640 * 480 * 3) == 0
frames = np.frombuffer(process.stdout, dtype=np.uint8).reshape(-1, 480, 640, 3)
rows = []
for index, frame in enumerate(frames):
    points, detector_stats = detect_markers(frame)
    colors = {}
    for color, (lower, upper) in DEFAULT_THRESHOLDS.items():
        mask = np.all((frame >= np.asarray(lower)) & (frame <= np.asarray(upper)), axis=2)
        yy, xx = np.nonzero(mask)
        n = len(xx)
        colors[color] = {
            "count": n,
            "span": [int(np.ptp(xx)), int(np.ptp(yy))] if n else [0, 0],
            "centroid": [float(xx.mean()), float(yy.mean())] if n else None,
            "bounds": [int(xx.min()), int(yy.min()), int(xx.max()), int(yy.max())] if n else None,
        }
    rows.append({"sample_index_at_1fps": index, "all_markers_valid": points is not None,
        "points": points.tolist() if points is not None else None, "all_color_stats": colors})
valid = [row for row in rows if row["all_markers_valid"]]
scene_path = root / "tools/obs-studio/portable/config/obs-studio/basic/scenes/FPGA.json"
scene = json.loads(scene_path.read_text(encoding="utf-8-sig"))
item = next(source for source in scene["sources"] if source.get("id") == "scene")["settings"]["items"][0]
record = {
    "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
    "original": str(original), "video": str(video.relative_to(root)),
    "video_sha256": hashlib.sha256(video.read_bytes()).hexdigest(),
    "source": "Actual camera through native FPGA, user-operated OBS target recording",
    "sampled_frames_1fps": len(rows), "valid_four_marker_samples": len(valid),
    "first_valid_sample": valid[0] if valid else None,
    "sample_25_seconds": rows[25] if len(rows) > 25 else None,
    "samples": rows,
    "obs_saved_scene_transform": {key: item.get(key) for key in ["pos", "scale", "bounds", "bounds_type", "crop_left", "crop_top", "crop_right", "crop_bottom"]},
    "qualification_limit": "OBS canvas was transformed/cropped and H264/NV12 are lossy. This checks visible colors and geometry availability, not exact MS7200 RGB thresholds or hardware corner coordinates. Native full source frame or in-board measurements needed for exact claims.",
    "actual_camera_correction_accepted": False,
}
(hardware / "native_target_input_20261011.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({key: record[key] for key in ["sampled_frames_1fps", "valid_four_marker_samples", "first_valid_sample", "sample_25_seconds", "qualification_limit"]}, ensure_ascii=False, indent=2))
