"""Save the first real optical rectification; do not overclaim continuity or FPS."""
from datetime import datetime, timezone
from pathlib import Path
import json

root = Path(__file__).resolve().parents[1]
hw = root / "results/hardware_20261009"
evidence = hw / "ddr_status_fpga_20261011_174046.json"
data = json.loads(evidence.read_text(encoding="utf-8-sig"))
probes = [s["probe"] for s in data["samples"]]
assert len(probes) == 25 and all(p["image_valid"] and not p["underrun"] for p in probes)
assert all(p["ddr_ready"] and p["selftest_passed"] and not p["engine_fault"] and not p["phy_fail"] and not p["align_error"] for p in probes)
assert all(p["rx_bad_captures"] == 0 for p in probes)
assert min(p["good_results"] for p in probes) == 1 and max(p["good_results"] for p in probes) == 2
record = {
    "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
    "evidence": str(evidence.relative_to(root)), "image_sha256": data["image_sha256"],
    "original_video": data["original_video"], "video_sha256": data["video_sha256"],
    "user_verbatim": "出现矩形校正图了，闪烁的绿红是什么",
    "decoded_samples": 25, "image_valid_samples": 25, "display_underrun_samples": 0,
    "successful_results_first_last": [1, 2], "new_completed_results_within_recording": 1,
    "first_real_camera_rectification_observed": True,
    "upright_test_page_visually_checked": True,
    "diagnostic_grid_masks_lower_part": True,
    "current_boot_ddr_bist_observed": True, "actual_camera_ddr_complete_capture_observed": True,
    "zero_bad_capture_samples": True,
    "continuous_marker_detection_accepted": False, "algorithm_update_fps_measured": False,
    "qualification_limit": "Actual FPGA-routed optical test page and real successful result counter verified. Diagnostic grid hides lower part. Valid-target duration was not independently captured, so this clip cannot establish steady correction rate or reliable marker detection across all 25 seconds.",
    "next": "Program retained qualified clean a4 image, record the full corrected page and stability; preserve all diagnostics and originals.",
}
path = hw / "first_real_camera_rectification_20261011.json"
path.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
state_path = hw / "ddr_camera_status_state_20261011.json"
state = json.loads(state_path.read_text(encoding="utf-8-sig"))
state.update(first_real_camera_rectification_observed=True,
    actual_target_correction_observed=True, current_boot_ddr_bist_observed=True,
    actual_camera_ddr_complete_capture_observed=True,
    evidence=str(path.relative_to(root)), current_receiver_probe_decoded=True,
    current_valid_camera_width_height_measured=True, successful_result_count=2,
    actual_camera_correction_accepted=False,
    pending=record["next"], qualification_limit=record["qualification_limit"])
state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
status_path = root / "docs/hardware_20261009.json"
status = json.loads(status_path.read_text(encoding="utf-8-sig"))
status.update(state, first_real_camera_rectification_evidence=str(path.relative_to(root)),
    capture_result="Actual camera test page visibly rectified, good result counter 1 -> 2; all 25 D205 samples image_valid and no display underrun. Full clean image and continuity verification pending.")
status_path.write_text(json.dumps(status, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("Recorded first real optical rectification; full-page/continuity acceptance remains pending.")
