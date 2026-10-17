"""Record the actual successful capture and failed marker stage, without claiming correction."""
from datetime import datetime, timezone
from pathlib import Path
import json
import shutil

root = Path(__file__).resolve().parents[1]
hw = root / "results/hardware_20261009"
first = hw / "ddr_status_fpga_20261011_143638.json"
latest = hw / "ddr_status_fpga_20261011.json"
if not first.exists():
    shutil.copyfile(latest, first)
data = json.loads(first.read_text(encoding="utf-8-sig"))
assert data["original_video"].endswith("2026-10-11 14-36-38.mp4")
probes = [s["probe"] for s in data["samples"]]
assert len(probes) == 37
assert all(p["ddr_ready"] and p["selftest_passed"] and p["rx_bad_captures"] == 0 for p in probes)
assert all(p["last_capture_samples"] == 307200 and p["last_capture_lines"] == 1080 and p["last_capture_flags"] == 4 for p in probes)
assert all(p["good_results"] == 0 and p["last_failure"] == 1 for p in probes)
state_path = hw / "ddr_camera_status_state_20261011.json"
state = json.loads(state_path.read_text(encoding="utf-8-sig"))
assert state["current_image_sha256"] == data["image_sha256"]
state.update(updated_at_utc=datetime.now(timezone.utc).isoformat(),
    actual_camera_ddr_complete_capture_observed=True, current_boot_ddr_bist_observed=True,
    current_receiver_probe_decoded=True,current_valid_camera_width_height_measured=True,
    actual_target_correction_observed=False, current_failed_stage="marker detection (code 1)",
    evidence=str(first.relative_to(root)),decoded_samples=37,
    capture_counter_first_last=[probes[0]["rx_good_captures"],probes[-1]["rx_good_captures"]],
    capture_bad_count=0,successful_result_count=0,
    marker_observation="Small target has insufficient/intermittent red and blue pixels, zero yellow hits; no valid whole marker set. Source timing/capture and DDR initialization pass this observation.",
    pending="Test independent large-marker target on current D205 image; collect actual colour counts before changing compiled thresholds. Original fixture/viewer and releases retained.")
state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
status_path = root / "docs/hardware_20261009.json"
status = json.loads(status_path.read_text(encoding="utf-8-sig"))
status.update(state,current_temporary_image=state["current_image"],
    current_temporary_image_sha256=state["current_image_sha256"],
    capture_result="Actual D205 clip: DDR BIST and 1920x1080 full frame sampling/drain observed; 1592..2024 captures, 0 bad captures, 0 corrected results; actual rejection is marker detection.")
status_path.write_text(json.dumps(status, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("Saved physical full-DDR capture success and actual small-target marker failure separately.")
