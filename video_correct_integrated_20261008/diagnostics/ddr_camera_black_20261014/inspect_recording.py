"""Inspect a fresh physical OBS recording attributed to the verified black image."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import numpy as np
from PIL import Image, ImageDraw

D = Path(__file__).resolve().parent
R = D.parents[1]
HW = R / "results/hardware_20261014_black"
FFMPEG = R / "tools/python_packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe"


def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8*1024*1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video", type=Path)
    args = ap.parse_args()
    original = args.video.resolve()
    state = json.loads((HW/"black_camera_state_20261014.json").read_text(encoding="utf-8"))
    program = R / state["last_program_log"]
    assert state["program_verify_passed"] and sha(program) == state["last_program_log_sha256"]
    assert program == max(HW.glob("program_black_*.log"), key=lambda p: p.stat().st_mtime)
    assert sha(R/state["current_image"]) == state["current_image_sha256"]
    assert original.stat().st_mtime > program.stat().st_mtime and original.stat().st_size > 0
    info = subprocess.run([str(FFMPEG), "-hide_banner", "-i", str(original)], capture_output=True)
    metadata = info.stderr.decode("utf-8", errors="replace")
    duration_match = re.search(r"Duration: (\d+):(\d+):([\d.]+)", metadata)
    assert duration_match, "Recording must be stopped and finalized before inspection"
    duration = int(duration_match[1])*3600 + int(duration_match[2])*60 + float(duration_match[3])
    fps_match = re.search(r"(\d+(?:\.\d+)?) fps", metadata)
    assert fps_match and re.search(r"\b1920x1080\b", metadata), metadata
    fps = float(fps_match[1])
    out = HW / ("black_probe_" + original.stem.replace(" ", "_").replace("-", ""))
    out.mkdir(exist_ok=False)
    (out/"metadata.txt").write_text(metadata, encoding="utf-8")
    digest = sha(original)
    saved = HW / ("black_camera_" + original.name)
    if saved.exists():
        assert sha(saved) == digest
    else:
        shutil.copyfile(original, saved)
    assert sha(saved) == digest
    seconds = min(duration, 60)
    command = [str(FFMPEG), "-hide_banner", "-loglevel", "error", "-i", str(original), "-t", str(seconds),
               "-an", "-vf", "crop=640:904:640:88,scale=64:904", "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1"]
    frames = []
    with (out/"decode.log").open("wb") as err:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=err)
        size = 64*904*3
        while True:
            data = process.stdout.read(size)
            if not data:
                break
            assert len(data) == size
            frame = np.frombuffer(data, dtype=np.uint8).reshape(904, 64, 3)
            mean = frame.mean(axis=(1,2))
            std = frame.std(axis=(1,2))
            dark = (mean < 55) & (std < 12)
            indices = np.flatnonzero(dark)
            ranges = [[int(x[0]), int(x[-1])] for x in np.split(indices, np.flatnonzero(np.diff(indices)>1)+1) if len(x)]
            frames.append({"index": len(frames), "encoded_seconds": len(frames)/fps,
                           "roi_mean": float(frame.mean()), "dark_rows": int(dark.sum()), "dark_row_ranges": ranges})
        assert process.wait() == 0
    assert frames
    times = sorted(set(round(t, 2) for t in (0.5, duration/4, duration/2, 3*duration/4, max(0, duration-0.5)) if 0<=t<duration))
    sheet = Image.new("RGB", (960*3, 570*2), "#202020")
    draw = ImageDraw.Draw(sheet)
    samples = []
    for i, t in enumerate(times):
        path = out / f"sample_{i:02d}_{t:.2f}s.png"
        result = subprocess.run([str(FFMPEG), "-hide_banner", "-loglevel", "error", "-ss", str(t), "-i", str(original),
                                 "-frames:v", "1", "-y", str(path)], capture_output=True)
        assert result.returncode == 0, result.stderr
        image = Image.open(path).convert("RGB")
        assert image.size == (1920,1080)
        image.thumbnail((960,540))
        x, y = i%3*960, i//3*570
        sheet.paste(image, (x,y))
        draw.text((x+5, y+545), f"{t:.2f}s | ACTUAL BLACK CAMERA RECORDING", fill="white")
        samples.append({"encoded_seconds": t, "file": str(path.relative_to(R))})
    sheet.save(out/"contact_sheet.jpg", quality=90)
    receipt = {"recorded_at_utc": datetime.now(timezone.utc).isoformat(), "original_video": str(original),
               "preserved_video": str(saved.relative_to(R)), "original_sha256": digest,
               "video_duration_encoded_seconds": duration, "encoded_fps": fps, "analyzed_frames": len(frames),
               "current_image": state["current_image"], "image_sha256": state["current_image_sha256"],
               "program_log": state["last_program_log"], "physical_route_confirmed_by_user": state["physical_route_confirmed_by_user"],
               "metrics": frames, "samples": samples, "contact_sheet": str((out/"contact_sheet.jpg").relative_to(R)),
               "full_page_visually_checked": False, "stable_picture_accepted": False, "actual_update_rate_measured": False,
               "qualification_limit": "Fresh physical recording; row metrics require picture review. Static repeated frames do not prove ongoing computation. Encoded FPS is not algorithm update rate."}
    (out/"probe.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({"probe": str(out/"probe.json"), "frames": len(frames), "duration": duration,
                      "whole_dark_frames": sum(f["dark_rows"]>890 for f in frames),
                      "max_dark_rows": max(f["dark_rows"] for f in frames),
                      "contact_sheet": str(out/"contact_sheet.jpg")}, indent=2))


if __name__ == "__main__":
    main()
