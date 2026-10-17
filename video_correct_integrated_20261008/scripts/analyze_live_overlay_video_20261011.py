"""Decode live receiver measurements only from recorded D104/B401 pixels."""
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
state = json.loads((hw / "bram_overlay_state_20261011.json").read_text(encoding="utf-8-sig"))
assert state["program_verify_passed"]
assert hashlib.sha256((root / state["current_image"]).read_bytes()).hexdigest() == state["current_image_sha256"]
original = args.video.resolve()
assert original.parent == Path("C:/Users/夏菲/Videos")
assert original.stat().st_mtime > (root / state["program_log"]).stat().st_mtime
name = "live_overlay_fpga_" + original.stem.replace(" ", "_").replace("-", "")
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
spec = importlib.util.spec_from_file_location("bram_decoder", root / "diagnostics/camera_live_bram_20261010/decode_status.py")
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
indices = list(range(0, len(records), 2))
sheet = Image.new("RGB", (480 * 4, 295 * ((len(indices) + 3) // 4)), "#202020")
draw = ImageDraw.Draw(sheet)
for j, sample in enumerate(indices):
    frame = Image.open(root / records[sample]["frame"]).convert("RGB")
    frame.thumbnail((480, 270))
    x, y = (j % 4) * 480, (j // 4) * 295
    sheet.paste(frame, (x, y))
    probe = records[sample].get("probe")
    label = f"{sample + 0.5:.1f}s" + (f" | {probe['rx_width']}x{probe['active_height']} live={probe['frame_valid']}" if probe else " | unreadable")
    draw.text((x + 5, y + 273), label, fill="white")
sheet_path = out / "contact_sheet.jpg"
sheet.save(sheet_path, quality=90)
record = {
    "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
    "original_video": str(original), "video_copy": str(video.relative_to(root)),
    "video_sha256": hashlib.sha256(video.read_bytes()).hexdigest(),
    "image": state["current_image"], "image_sha256": state["current_image_sha256"],
    "route": "R50 -> FPGA HDMI-IN -> FPGA HDMI-OUT -> VC-002Pro -> USB PC, as last explicitly confirmed",
    "decode_process_succeeded": True, "sample_count": len(records),
    "decoded_grid_samples": sum("probe" in r for r in records),
    "contact_sheet": str(sheet_path.relative_to(root)), "samples": records,
    "limit": "Encoded OBS frames provide live hardware state only when both diagnostic signatures match. Sticky seen flags alone do not prove current input; live buffer validity and consistent dimensions must be reviewed. Not correction FPS or long-term acceptance.",
}
path = hw / "live_overlay_fpga_20261011.json"
path.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"record": str(path), "samples": len(records), "grids": record["decoded_grid_samples"],
    "probes": [{"s": r["approx_encoded_video_seconds"], "width": r["probe"]["rx_width"],
    "height": r["probe"]["active_height"], "period": r["probe"]["rx_hs_period"],
    "vs_edges": r["probe"]["vs_edge_count"], "live": r["probe"]["frame_valid"],
    "frequency": r["probe"]["frequency_registers"]} for r in records if "probe" in r],
    "contact_sheet": str(sheet_path)}, ensure_ascii=False, indent=2))
