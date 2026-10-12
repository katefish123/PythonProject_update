"""Record an actual Program/Verify result separately from immutable release files."""
import argparse
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json

parser = argparse.ArgumentParser()
parser.add_argument("program_log", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
log = args.program_log.resolve()
assert log.parent == root / "results/hardware_20261009"
text = log.read_text(encoding="utf-8-sig", errors="replace")
assert "COMMAND[Program] execute successfully" in text and "COMMAND[Verify] execute successfully" in text
assert not any(token in text for token in ["execute fail", "exec failed", "Fail to compare", "** Error"])
image = "release/camera_bram_overlay_20261011/camera_live_bram_top.sbit"
digest = hashlib.sha256((root / image).read_bytes()).hexdigest()
assert digest == "b6f8ddafba670fffe2b9045a4c84cceb4c41c043551753c2172d1394e0154a2f"
stamp = datetime.now(timezone.utc).isoformat()
record = {
    "recorded_at_utc": stamp, "current_image": image, "current_image_sha256": digest,
    "program_log": str(log.relative_to(root)), "program_log_sha256": hashlib.sha256(log.read_bytes()).hexdigest(),
    "program_verify_passed": True, "flash_modified": False,
    "phase": "Read real live camera width/height/sync with a continuously visible status overlay",
    "previous_accepted_coarse_camera_evidence": "results/hardware_20261009/bram_diagnostic_fpga_20261011.json",
    "retained_previous_working_image": "release/camera_live_bram_reconnect_20261010/camera_live_bram_top.sbit",
    "actual_camera_display_accepted_for_current_image": False, "actual_camera_correction_accepted": False,
    "current_receiver_probe_decoded": False, "current_valid_camera_width_height_measured": False,
    "paused_by_user": False, "resumed_by_user": True, "computer_use_paused_by_user": True,
    "pending": "User manually deactivates/reactivates OBS source after programming, then records 10-15 seconds with camera connected and live; decode D104/B401 during actual camera input. No desktop automation.",
}
path = root / "results/hardware_20261009/bram_overlay_state_20261011.json"
path.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
status_path = root / "docs/hardware_20261009.json"
status = json.loads(status_path.read_text(encoding="utf-8-sig"))
status.update(record, last_update_utc=stamp, current_temporary_image=image,
    current_temporary_image_sha256=digest, bitstream_sha256=digest,
    latest_camera_live_state=str(path.relative_to(root)),
    capture_result="Live-overlay diagnostic Program/Verify passed; waiting for actual camera input recording with readable state.",
    actual_camera_display_accepted=False)
status_path.write_text(json.dumps(status, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("Recorded programmed live overlay; previous coarse camera evidence retained.")
