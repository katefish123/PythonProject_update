"""Save the physically checked baseline as a reversible fallback for detail work."""
from datetime import datetime,timezone
from pathlib import Path
import json

root=Path(__file__).resolve().parents[1]
hw=root/"results/hardware_20261009"
path=hw/"clean_corrected_camera_20261011_181218.json"
evidence=json.loads(path.read_text(encoding="utf-8-sig"))
assert evidence["image_sha256"]=="a4bd7f42732c100b598cb974e03477877aab4032e39f6de558bb245d666e232e"
assert evidence["white_page_candidate_frames"]==1404 and evidence["non_page_frames_after_first_page"]==0
assert evidence["black_like_frames_after_first_page"]==0 and evidence["minimum_outside_window_dark_ratio_during_page"]==1
evidence.update(full_page_visually_checked=True,diagnostic_grid_absent_visually_checked=True,
    user_verbatim="整校正录像已保存 ，有完整矩形图 ，没有别的异样，但是好像字迹有点模糊？",
    continuous_clean_page_display_observed_seconds_approx=1404/30,
    clarity_accepted=False,working_baseline_preserved=True,
    qualification_limit="Real full clean rectification and short stable/held display accepted. Optical/processing sharpness still needs improvement. Continuous update rate and long-run behavior are not accepted by a static or held frame.")
path.write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
(hw/"clean_camera_video_latest_20261011.json").write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
state_path=hw/"clean_camera_state_20261011.json"
state=json.loads(state_path.read_text(encoding="utf-8-sig"))
assert state["current_image_sha256"]==evidence["image_sha256"]
state.update(actual_camera_correction_accepted=True,actual_camera_display_accepted_for_current_image=True,
    actual_camera_display_accepted=True,full_clean_page_visually_checked=True,
    short_clean_page_display_observed_seconds_approx=1404/30,
    clarity_accepted=False,updated_at_utc=datetime.now(timezone.utc).isoformat(),
    evidence=str(path.relative_to(root)),qualification_limit=evidence["qualification_limit"],
    pending="Prepare and qualify independent 960x540-source / 640x904-result clone for improved detail. Keep this actually verified 320x452 baseline loaded until the new clone passes checks.")
state_path.write_text(json.dumps(state,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
(hw/"working_clean_baseline_verified_20261011.json").write_text(json.dumps(state,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
status_path=root/"docs/hardware_20261009.json"
status=json.loads(status_path.read_text(encoding="utf-8-sig"))
status.update(state,capture_result="Actual complete clean 320x452 correction verified; about 46.8 seconds after first page has no blackouts or fallback bars. Sharpness upgrade in a separate clone, baseline retained.")
status_path.write_text(json.dumps(status,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print("Saved physically verified clean baseline; detail/continuous update acceptance remains separate.")
