"""Preserve real receiver measurements independently of later board images."""
from datetime import datetime, timezone
from pathlib import Path
import json

root = Path(__file__).resolve().parents[1]
path = root / "results/hardware_20261009/live_overlay_fpga_20261011.json"
data = json.loads(path.read_text(encoding="utf-8-sig"))
probes = [s["probe"] for s in data["samples"]]
assert len(probes) == 18
assert all(p["frame_valid"] and p["rx_width"] == 1920 and p["active_height"] == 1080 for p in probes)
assert all(not p["config_error"] and not p["ack_error"] and p["rx_done"] and p["tx_done"] for p in probes)
record = {
    "recorded_at_utc": datetime.now(timezone.utc).isoformat(), "evidence": str(path.relative_to(root)),
    "evidence_image_sha256": data["image_sha256"], "valid_samples": 18,
    "rx_width": 1920, "active_height": 1080,
    "hs_period_range": [min(p["rx_hs_period"] for p in probes), max(p["rx_hs_period"] for p in probes)],
    "vs_edges_first_last": [probes[0]["vs_edge_count"], probes[-1]["vs_edge_count"]],
    "vs_edge_rate_over_approx_encoded_video_seconds": (probes[-1]["vs_edge_count"] - probes[0]["vs_edge_count"]) / 17,
    "camera_configuration_errors_seen": False, "coarse_buffer_valid_all_samples": True,
    "user_motion_verbatim": "新诊断录像已保存 ，上方取景跟着手变化",
    "limit": "Current short BRAM diagnostic camera input only. VS counter over encoded video seconds is an approximate consistency check, not calibrated HDMI timing, native clarity, long-term stability or correction throughput.",
}
out = root / "results/hardware_20261009/live_camera_input_verified_20261011.json"
out.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
state_path = root / "results/hardware_20261009/bram_overlay_state_20261011.json"
state = json.loads(state_path.read_text(encoding="utf-8-sig"))
state.update(actual_camera_display_accepted_for_current_image=True, current_receiver_probe_decoded=True,
    current_valid_camera_width_height_measured=True, evidence=str(out.relative_to(root)),
    pending="Build full-DDR D205 state observer to distinguish capture, DDR drain, marker and processing outcomes on real target.")
state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
status_path = root / "docs/hardware_20261009.json"
status = json.loads(status_path.read_text(encoding="utf-8-sig"))
assert status["current_image_sha256"] == data["image_sha256"]
status.update(current_receiver_probe_decoded=True,current_valid_camera_width_height_measured=True,
    actual_camera_display_accepted=True,actual_camera_display_accepted_for_current_image=True,
    camera_rx_measured_width=1920,camera_rx_measured_active_height=1080,
    camera_rx_diagnostic_evidence=str(out.relative_to(root)),pending=state["pending"],
    capture_result="18 decoded live D104/B401 samples all show real 1920x1080 input and valid coarse buffer; full DDR correction remains unaccepted.")
status_path.write_text(json.dumps(status, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("Saved real live-camera input measurements; calibration/correction acceptance unchanged.")
