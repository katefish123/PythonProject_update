"""Save the user's actual FPGA-route observation without claiming native acceptance."""
from datetime import datetime, timezone
from pathlib import Path
import json

root = Path(__file__).resolve().parents[1]
stamp = datetime.now(timezone.utc).isoformat()
state_path = root / "results/hardware_20261009/receiver_diagnostic_after_rewire_20261011.json"
state = json.loads(state_path.read_text(encoding="utf-8-sig"))
assert state["current_image_sha256"] == "be1a72cade3008e25cff3f6925bf6347fea8211da6e5447fdd82ef137e7f5212"
state.update(
    updated_at_utc=stamp,
    actual_coarse_camera_motion_user_confirmed=True,
    current_user_report_verbatim="粗预览已跟着手变化",
    preceding_user_report_verbatim="只有相机变化，OBS 不变",
    obs_source_manual_deactivate_activate_completed=True,
    obs_log_source_reactivated_at_local="2026-10-11 13:24:22.997",
    actual_camera_display_accepted=True,
    acceptance_limit="User confirms coarse BRAM preview follows hand after OBS source refresh on explicitly verified FPGA route. Native clarity, long-term stability, full DDR correction and actual FPS remain unaccepted.",
    current_receiver_probe_decoded=False,
    pending="Manual recording of current coarse motion followed by input unplug diagnostic grid and restoration. Read receiver state from actual recorded frames; no desktop automation.",
)
state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
status_path = root / "docs/hardware_20261009.json"
status = json.loads(status_path.read_text(encoding="utf-8-sig"))
status.update(
    last_update_utc=stamp,
    actual_coarse_camera_motion_user_confirmed=True,
    actual_camera_display_accepted=True,
    actual_camera_display_accepted_for_current_image=True,
    current_fpga_video_observation=state["current_user_report_verbatim"],
    capture_result=state["acceptance_limit"],
    qualification_limit=state["acceptance_limit"],
    pending=state["pending"],
    obs_source_manual_deactivate_activate_completed=True,
    latest_camera_live_state=str(state_path.relative_to(root)),
    short_native_camera_continuity_verified_seconds=None,
    short_native_camera_continuity_decoded_frames=None,
    short_native_camera_black_like_frames=None,
    previous_native_test_duration_seconds=None,
    previous_native_decoded_frames=None,
    previous_native_black_like_frames=None,
    latest_recordings_direct_camera_scope="Today's 11:59/12:09/12:55 videos bypassed FPGA; statistics remain in their corrected direct-camera evidence JSONs.",
)
status_path.write_text(json.dumps(status, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("Saved user-confirmed coarse FPGA motion after manual OBS source refresh.")
