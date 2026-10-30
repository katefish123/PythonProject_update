"""Inspect the actual user-recorded camera clip, never synthetic preview frames."""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess
import numpy as np

root = Path(__file__).resolve().parents[1]
hardware = root / "results/hardware_20261009"
ffmpeg = root / "tools/python_packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe"
original = Path("C:/Users/夏菲/Videos/2026-10-11 11-59-06.mp4")
video = hardware / "native_camera_motion_20261011_115906.mp4"
shutil.copyfile(original, video)
source_original = Path("C:/Users/夏菲/Videos/Screenshot 2026-10-11 11-58-13.png")
source_copy = hardware / "native_camera_source_20261011_115813.png"
shutil.copyfile(source_original, source_copy)
result = subprocess.run(
    [str(ffmpeg), "-hide_banner", "-loglevel", "info", "-i", str(video),
     "-map", "0:v:0", "-an", "-vf", "scale=160:90", "-pix_fmt", "gray", "-f", "rawvideo", "pipe:1"],
    capture_output=True, check=False,
)
stderr = result.stderr.decode("utf-8", errors="replace")
(hardware / "native_camera_motion_decode_20261011.log").write_text(stderr, encoding="utf-8")
assert result.returncode == 0, stderr[-2000:]
assert len(result.stdout) % (160 * 90) == 0
frames = np.frombuffer(result.stdout, dtype=np.uint8).reshape(-1, 90, 160)
assert len(frames) > 300, len(frames)
means = frames.mean(axis=(1, 2))
bright_fraction = (frames > 16).mean(axis=(1, 2))
black_like = (means < 2) | (bright_fraction < 0.005)
changes = np.abs(np.diff(frames.astype(np.int16), axis=0)).mean(axis=(1, 2))
peak_frame = int(np.argmax(changes)) + 1
peak_copy = hardware / "native_camera_motion_peak_20261011.png"
extract = subprocess.run(
    [str(ffmpeg), "-hide_banner", "-loglevel", "error", "-i", str(video),
     "-vf", f"select=eq(n\\,{peak_frame})", "-frames:v", "1", "-y", str(peak_copy)],
    capture_output=True, check=False,
)
assert extract.returncode == 0, extract.stderr.decode("utf-8", errors="replace")
duration = re.search(r"Duration: (\d+):(\d+):(\d+\.\d+)", stderr)
assert duration
seconds = int(duration[1]) * 3600 + int(duration[2]) * 60 + float(duration[3])
record = {
    "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
    "original_video": str(original), "video_copy": str(video.relative_to(root)),
    "video_sha256": hashlib.sha256(video.read_bytes()).hexdigest(),
    "source_original": str(source_original), "source_copy": str(source_copy.relative_to(root)),
    "source_sha256": hashlib.sha256(source_copy.read_bytes()).hexdigest(),
    "duration_container_seconds": seconds,
    "decoded_video_frames": len(frames),
    "encoded_recording_nominal_fps": 30,
    "black_like_decoded_frames": int(black_like.sum()),
    "black_like_frame_indices": np.flatnonzero(black_like).tolist(),
    "minimum_mean_luma": float(means.min()),
    "maximum_mean_luma": float(means.max()),
    "minimum_bright_fraction": float(bright_fraction.min()),
    "successive_pairs_mean_difference_gt_1": int((changes > 1).sum()),
    "largest_pair_mean_difference": float(changes.max()),
    "peak_change_frame_index": peak_frame,
    "peak_frame": str(peak_copy.relative_to(root)),
    "decode_process_succeeded": True,
    "user_reported_no_flicker_or_black": True,
    "real_camera_motion_independently_visually_checked": False,
    "hardware_input_fps_measured": False,
    "algorithm_update_fps_measured": False,
    "qualification_limit": "Short recorded OBS canvas check only; encoded fps is not HDMI input fps or correction throughput. Motion candidate requires visual review. Does not prove long-term stability or explain earlier flicker.",
}
(hardware / "native_camera_motion_20261011.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(record, ensure_ascii=False, indent=2))
