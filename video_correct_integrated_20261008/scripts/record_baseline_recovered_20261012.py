"""Accept only the inspected recovery recording and retain the clarity/FPS limits."""
from datetime import datetime,timezone
from pathlib import Path
import hashlib
import json

R=Path(__file__).resolve().parents[1]
hw=R/"results/hardware_20261009"
path=hw/"clean_camera_state_20261011.json"
state=json.loads(path.read_text(encoding="utf-8-sig"))
assert state["current_image_sha256"]=="a4bd7f42732c100b598cb974e03477877aab4032e39f6de558bb245d666e232e"
assert state["program_log"].endswith("program_ddr_camera_reconnect_20261011_235140.log")
evidence_path=hw/"clean_corrected_camera_20261012_003742.json"
video=json.loads(evidence_path.read_text(encoding="utf-8-sig"))
assert video["image_sha256"]==state["current_image_sha256"]
assert video["decode_succeeded"] and video["non_page_frames_after_first_page"]==0 and video["black_like_frames_after_first_page"]==0
assert video["decoded_frames"]==1765 and video["white_page_candidate_frames"]==1567
assert hashlib.sha256((R/video["video_copy"]).read_bytes()).hexdigest()==video["video_sha256"]
video.update(full_page_visually_checked=True,
    visual_review="First page is optically defocused; middle and last show the upright complete test sheet with all four colored corners, text/grid, full prescribed window and dark surroundings. Text remains soft with screen moire.",
    current_boot_complete_correction_observed=True,short_recording_stable_picture_accepted=True,
    clarity_improvement_accepted=False,continuous_real_correction_update_accepted=False)
evidence_path.write_text(json.dumps(video,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
(hw/"clean_camera_video_latest_20261011.json").write_text(json.dumps(video,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
stamp=datetime.now(timezone.utc).isoformat()
record={"recorded_at_utc":stamp,"current_image":state["current_image"],"image_sha256":state["current_image_sha256"],
    "program_log":state["program_log"],"physical_route":"R50 -> FPGA HDMI-IN -> FPGA HDMI-OUT -> VC-002Pro -> PC USB",
    "hdmi_output_recovered_user_report":"Colorbars after baseline restore, followed by complete corrected rectangle during target test.",
    "evidence":str(evidence_path.relative_to(R)),"video_sha256":video["video_sha256"],
    "full_page_visually_checked":True,"stable_encoded_picture_seconds_approximately":1567/30,
    "current_boot_optical_correction_accepted":True,"current_boot_picture_recovery_accepted":True,
    "clarity_improvement_accepted":False,"long_term_stability_accepted":False,"algorithm_update_fps_measured":False,
    "limit":"Frame-hold behavior is permitted; encoded30fps and a stable optical page cannot establish actual algorithm update FPS. Does not grant any high-detail image acceptance."}
receipt=hw/"baseline_recovered_verified_20261012.json"
receipt.write_text(json.dumps(record,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
state.update(recorded_at_utc=stamp,phase="Baseline actual full optical correction recovered; high-detail read-ahead candidate in preparation",
    physical_route_current=record["physical_route"],current_boot_hdmi_output_user_confirmed=True,
    actual_camera_correction_accepted=True,actual_camera_display_accepted_for_current_image=True,
    actual_camera_display_accepted=True,short_recording_stable_picture_accepted=True,
    current_boot_recovery_evidence=str(receipt.relative_to(R)),current_failed_stage=None,
    pending="Keep this working baseline while the independent high-detail prefetch clone passes shared-memory, full-pixel, timing and programming checks. No user operation needed during the build.")
path.write_text(json.dumps(state,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
main_path=R/"docs/hardware_20261009.json"
main=json.loads(main_path.read_text(encoding="utf-8-sig"))
assert main["current_image_sha256"]==state["current_image_sha256"]
main.update(state,last_update_utc=stamp,capture_result="Current a4 baseline optical correction recovered after HDMI unplug; actual 00:37:42 recording reviewed, full page and about52s post-first-page without blackout or fallback. Detail/moire still unresolved.")
main_path.write_text(json.dumps(main,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print("Recorded independently reviewed baseline recovery; high-detail/FPS/long-run acceptance withheld.")
