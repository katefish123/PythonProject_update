"""Inspect real, explicitly FPGA-routed OBS video and decode its actual grid."""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import importlib.util
import json
import shutil
import subprocess
from PIL import Image, ImageDraw
import numpy as np

root = Path(__file__).resolve().parents[1]
hw = root / "results/hardware_20261009"
original = Path("C:/Users/夏菲/Videos/2026-10-11 13-39-57.mp4")
video = hw / "bram_diagnostic_fpga_20261011_133957.mp4"
out = hw / "bram_diagnostic_fpga_20261011_133957"
out.mkdir(exist_ok=True)
shutil.copyfile(original, video)
ffmpeg = root / "tools/python_packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe"
result = subprocess.run([str(ffmpeg), "-hide_banner", "-loglevel", "info", "-i", str(video),
    "-an", "-vf", "fps=1", "-y", str(out / "frame_%03d.png")], capture_output=True)
log = result.stderr.decode("utf-8", errors="replace")
(out / "decode.log").write_text(log, encoding="utf-8")
assert result.returncode == 0, log[-2000:]
spec = importlib.util.spec_from_file_location("bram_decoder", root / "diagnostics/camera_live_bram_20261010/decode_status.py")
decoder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(decoder)
records = []
previous = None
for i, path in enumerate(sorted(out.glob("frame_*.png"))):
    frame = Image.open(path).convert("RGB")
    small = np.asarray(frame.resize((160, 90))).astype(np.int16)
    record = {"sample_index": i, "approx_seconds": i + 0.5, "frame": str(path.relative_to(root)), "size": list(frame.size)}
    if previous is not None:
        record["mean_abs_change_from_prior_sample"] = float(np.abs(small - previous).mean())
    previous = small
    try:
        record["probe"] = decoder.decode(path)
    except ValueError as error:
        record["probe_decode_error"] = str(error)
    records.append(record)
samples = list(range(0, len(records), 3))
sheet = Image.new("RGB", (480 * 4, 295 * ((len(samples) + 3) // 4)), "#202020")
draw = ImageDraw.Draw(sheet)
for j, sample in enumerate(samples):
    frame = Image.open(root / records[sample]["frame"]).convert("RGB")
    frame.thumbnail((480, 270))
    x, y = (j % 4) * 480, (j // 4) * 295
    sheet.paste(frame, (x, y))
    draw.text((x + 5, y + 273), f"{sample + 0.5:.1f}s | " + ("GRID" if "probe" in records[sample] else "camera / other"), fill="white")
sheet_path = out / "contact_sheet.jpg"
sheet.save(sheet_path, quality=90)
record = {
    "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
    "original_video": str(original), "video_copy": str(video.relative_to(root)),
    "video_sha256": hashlib.sha256(video.read_bytes()).hexdigest(),
    "route": "R50 -> FPGA HDMI-IN -> FPGA HDMI-OUT -> VC-002Pro -> USB PC, explicitly confirmed by user",
    "image": "be1a72cade3008e25cff3f6925bf6347fea8211da6e5447fdd82ef137e7f5212",
    "user_verbatim": "诊断录像已保存  ，恢复取景但是还是很糊",
    "obs_canvas_fit_confirmed_by_saved_scene": True,
    "decode_process_succeeded": True,
    "sample_count": len(records),
    "decoded_grid_samples": sum("probe" in r for r in records),
    "contact_sheet": str(sheet_path.relative_to(root)),
    "samples": records,
    "limit": "One-second samples of actual encoded OBS canvas, not a measurement of correction FPS or long-term acceptance. Receiver counters decoded only when both D104/B401 signatures match.",
}
path = hw / "bram_diagnostic_fpga_20261011.json"
path.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"record": str(path), "samples": len(records), "grids": record["decoded_grid_samples"],
    "first_probe": next((r["probe"] for r in records if "probe" in r), None),
    "contact_sheet": str(sheet_path)}, ensure_ascii=False, indent=2))
