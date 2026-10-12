"""Preserve a post-program real target recording and decode physical D205 cells."""
import argparse
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import importlib.util
import json
import shutil
import subprocess
from PIL import Image, ImageDraw

parser = argparse.ArgumentParser()
parser.add_argument("video", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
hw = root / "results/hardware_20261009"
state = json.loads((hw / "ddr_camera_status_state_20261011.json").read_text(encoding="utf-8-sig"))
assert state["program_verify_passed"]
assert hashlib.sha256((root / state["current_image"]).read_bytes()).hexdigest() == state["current_image_sha256"]
original = args.video.resolve()
assert original.parent == Path("C:/Users/夏菲/Videos")
assert original.stat().st_mtime > (root / state["program_log"]).stat().st_mtime
name = "ddr_status_fpga_" + original.stem.replace(" ", "_").replace("-", "")
video = hw / (name + ".mp4")
out = hw / name
out.mkdir(exist_ok=True)
shutil.copyfile(original, video)
ffmpeg = root / "tools/python_packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe"
result = subprocess.run([str(ffmpeg), "-hide_banner", "-loglevel", "info", "-i", str(video),
    "-an", "-vf", "fps=1", "-y", str(out / "frame_%03d.png")], capture_output=True)
log = result.stderr.decode("utf-8", errors="replace")
(out / "decode.log").write_text(log, encoding="utf-8")
assert result.returncode == 0, log[-2000:]
spec = importlib.util.spec_from_file_location("ddr_decoder", root / "diagnostics/ddr_camera_status_20261011/decode_status.py")
decoder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(decoder)
records = []
for i, path in enumerate(sorted(out.glob("frame_*.png"))):
    record = {"sample_index": i, "approx_encoded_video_seconds": i + 0.5, "frame": str(path.relative_to(root))}
    try:
        record["probe"] = decoder.decode(path)
    except ValueError as error:
        record["probe_decode_error"] = str(error)
    records.append(record)
indices = list(range(0, len(records), 4))
sheet = Image.new("RGB", (480 * 4, 295 * ((len(indices) + 3) // 4)), "#202020")
draw = ImageDraw.Draw(sheet)
for j, sample in enumerate(indices):
    frame = Image.open(root / records[sample]["frame"]).convert("RGB")
    frame.thumbnail((480, 270))
    x, y = (j % 4) * 480, (j // 4) * 295
    sheet.paste(frame, (x, y))
    probe = records[sample].get("probe")
    label = f"{sample + 0.5:.1f}s" + (f" | captured={probe['rx_good_captures']} good={probe['good_results']} fail={probe['last_failure']}" if probe else " | unreadable")
    draw.text((x + 5, y + 273), label, fill="white")
sheet_path = out / "contact_sheet.jpg"
sheet.save(sheet_path, quality=90)
record = {
    "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
    "original_video": str(original), "video_copy": str(video.relative_to(root)),
    "video_sha256": hashlib.sha256(video.read_bytes()).hexdigest(),
    "image": state["current_image"], "image_sha256": state["current_image_sha256"],
    "decode_process_succeeded": True, "sample_count": len(records),
    "decoded_grid_samples": sum("probe" in r for r in records),
    "contact_sheet": str(sheet_path.relative_to(root)), "samples": records,
    "limit": "Real encoded OBS canvas with uniquely identified D205 cells; require visual/counter review before correction acceptance. Not a substitute for actual picture or throughput measurement.",
}
path = hw / "ddr_status_fpga_20261011.json"
immutable_path = hw / (name + ".json")
immutable_path.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
path.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"record": str(path), "samples": len(records), "grids": record["decoded_grid_samples"],
    "probes": [{"s": r["approx_encoded_video_seconds"], "ddr_ready": r["probe"]["ddr_ready"],
    "bist": r["probe"]["selftest_passed"], "captures": r["probe"]["rx_good_captures"],
    "capture_bad": r["probe"]["rx_bad_captures"], "samples": r["probe"]["last_capture_samples"],
    "lines": r["probe"]["last_capture_lines"], "capture_flags": r["probe"]["last_capture_flags"],
    "good_results": r["probe"]["good_results"], "rejected": r["probe"]["rejected_results"],
    "failure": r["probe"]["last_failure"], "session": r["probe"]["session_state"],
    "processor": r["probe"]["processor_state"], "counts": r["probe"]["marker_counts"],
    "xspans": r["probe"]["marker_x_spans"], "yspans": r["probe"]["marker_y_spans"],
    "ui_written": r["probe"]["ui_packets_written"]} for r in records if "probe" in r],
    "contact_sheet": str(sheet_path)}, ensure_ascii=False, indent=2))
