"""Inspect actual complete clean correction; encoded FPS is not processing FPS."""
import argparse
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import numpy as np

parser = argparse.ArgumentParser()
parser.add_argument("video", type=Path)
parser.add_argument("--hires", action="store_true")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
hw = root / "results/hardware_20261009"
state_file = "hires_camera_state_20261011.json" if args.hires else "clean_camera_state_20261011.json"
state = json.loads((hw / state_file).read_text(encoding="utf-8-sig"))
assert state["program_verify_passed"] and not state["diagnostic_grid_present"]
original = args.video.resolve()
assert original.parent == Path("C:/Users/夏菲/Videos")
assert original.stat().st_mtime > (root / state["program_log"]).stat().st_mtime
name = ("hires_corrected_camera_" if args.hires else "clean_corrected_camera_") + original.stem.replace(" ", "_").replace("-", "")
video = hw / (name + ".mp4")
shutil.copyfile(original, video)
ffmpeg = root / "tools/python_packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe"
def read_frames(filter_text, width, height, suffix):
    result = subprocess.run([str(ffmpeg), "-hide_banner", "-loglevel", "info", "-i", str(video),
        "-map", "0:v:0", "-an", "-vf", filter_text, "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1"], capture_output=True)
    log = result.stderr.decode("utf-8", errors="replace")
    (hw / (name + suffix + ".decode.log")).write_text(log, encoding="utf-8")
    assert result.returncode == 0, log[-2000:]
    assert len(result.stdout) % (width * height * 3) == 0
    return np.frombuffer(result.stdout, dtype=np.uint8).reshape(-1, height, width, 3)
roi = read_frames("crop=640:904:640:88,scale=64:90", 64, 90, "_roi")
small = read_frames("scale=192:108", 192, 108, "_full")
assert len(roi) == len(small) and len(roi) > 150
maximum, minimum = roi.max(axis=3), roi.min(axis=3)
neutral = maximum.astype(np.int16) - minimum.astype(np.int16) < 35
bright_neutral_fraction = (neutral & (roi.mean(axis=3) > 110)).mean(axis=(1, 2))
means = roi.mean(axis=(1, 2, 3))
white_page = (bright_neutral_fraction > 0.55) & (means > 100)
black_like = (means < 55) & (roi.std(axis=(1, 2, 3)) < 10)
changes = np.abs(np.diff(roi.astype(np.int16), axis=0)).mean(axis=(1, 2, 3))
indices = np.flatnonzero(white_page)
outside = np.ones((108,192), dtype=bool)
outside[7:101,62:130] = False # Conservative border around the prescribed display window.
outside_dark = (small.max(axis=3)[:, outside] < 64).mean(axis=1)
frame_paths = []
if len(indices):
    selected = [int(indices[0]), int(indices[len(indices)//2]), int(indices[-1])]
    for label, index in zip(["first", "middle", "last"], selected):
        image = hw / (name + "_" + label + ".png")
        result = subprocess.run([str(ffmpeg), "-hide_banner", "-loglevel", "error", "-i", str(video),
            "-vf", f"select='eq(n,{index})'", "-frames:v", "1", "-y", str(image)], capture_output=True)
        assert result.returncode == 0, result.stderr.decode("utf-8", errors="replace")
        frame_paths.append(str(image.relative_to(root)))
record = {
    "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
    "original_video": str(original), "video_copy": str(video.relative_to(root)), "video_sha256": hashlib.sha256(video.read_bytes()).hexdigest(),
    "image": state["current_image"], "image_sha256": state["current_image_sha256"],
    "decoded_frames": len(roi), "decode_succeeded": True,
    "white_page_candidate_frames": int(white_page.sum()), "black_like_window_frames": int(black_like.sum()),
    "first_white_page_frame": int(indices[0]) if len(indices) else None,
    "last_white_page_frame": int(indices[-1]) if len(indices) else None,
    "non_page_frames_after_first_page": int((~white_page[int(indices[0]):]).sum()) if len(indices) else None,
    "black_like_frames_after_first_page": int(black_like[int(indices[0]):].sum()) if len(indices) else None,
    "minimum_outside_window_dark_ratio_during_page": float(outside_dark[indices].min()) if len(indices) else None,
    "largest_successive_roi_mean_difference": float(changes.max()),
    "frames_requiring_visual_check": frame_paths,
    "full_page_visually_checked": False, "continuous_real_correction_update_accepted": False,
    "algorithm_update_fps_measured": False,
    "limit": "Candidate detection on actual OBS video, requiring visual review of the full prescribed rectangle. Stable held frame is allowed and cannot establish live update FPS. Encoded recording rate is not algorithm throughput.",
}
path = hw / (name + ".json")
path.write_text(json.dumps(record,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
(hw / ("hires_camera_video_latest_20261011.json" if args.hires else "clean_camera_video_latest_20261011.json")).write_text(json.dumps(record,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print(json.dumps(record,ensure_ascii=False,indent=2))
