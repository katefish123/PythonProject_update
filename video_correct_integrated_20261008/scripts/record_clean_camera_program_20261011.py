"""Record qualified clean output without borrowing current-boot diagnostic acceptance."""
import argparse
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json

parser = argparse.ArgumentParser()
parser.add_argument("program_log", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
hw = root / "results/hardware_20261009"
log = args.program_log.resolve()
assert log.parent == hw
text = log.read_text(encoding="utf-8-sig", errors="replace")
image = "release/ddr_camera_reconnect_20261011/video_correct_ddr_top.sbit"
assert (root / image).as_posix() in text
assert "COMMAND[Program] execute successfully" in text and "COMMAND[Verify] execute successfully" in text
assert not any(token in text for token in ["execute fail", "exec failed", "Fail to compare", "** Error"])
digest = hashlib.sha256((root / image).read_bytes()).hexdigest()
assert digest == "a4bd7f42732c100b598cb974e03477877aab4032e39f6de558bb245d666e232e"
stamp = datetime.now(timezone.utc).isoformat()
record = {
    "recorded_at_utc": stamp,"current_image": image,"current_image_sha256": digest,
    "program_log": str(log.relative_to(root)),"program_verify_passed": True,
    "program_log_sha256": hashlib.sha256(log.read_bytes()).hexdigest(),"flash_modified": False,
    "phase": "Full-page real camera correction with clean HDMI output, diagnostic grid removed",
    "first_real_camera_rectification_observed": True,
    "first_real_camera_rectification_evidence": "results/hardware_20261009/first_real_camera_rectification_20261011.json",
    "previous_verified_scope": "D205 image visibly rectifies real optical page; 25 samples valid, no underrun; counter 1 -> 2. This is historical after current reprogramming.",
    "diagnostic_grid_present": False,
    "actual_camera_correction_accepted": False,"actual_camera_display_accepted_for_current_image": False,
    "current_boot_ddr_bist_observed": False,"current_receiver_probe_decoded": False,
    "current_valid_camera_width_height_measured": False,"current_failed_stage": None,
    "capture_counter_first_last": None,"capture_bad_count": None,"successful_result_count": None,
    "source_sampling": [640,480],"processed_output": [320,452],"hdmi_output": [1920,1080],
    "display_window": {"x":640,"y":88,"width":640,"height":904},
    "algorithm_update_fps_measured": False,"long_term_camera_display_verified": False,
    "computer_use_paused_by_user": True,"original_A_B_C_modified": False,"original_target_modified": False,
    "project": "diagnostics/ddr_camera_reconnect_20261011/results/video_correct_ddr_reconnect.pds",
    "source_snapshot": "release/ddr_camera_reconnect_20261011/source_snapshot.zip",
    "pending": "Real clean-output recording with large-marker white page filling camera view for about 40 seconds, then close target and record held result. Verify full page, no synthetic bars, blackouts or disruptive flicker.",
}
path = hw / "clean_camera_state_20261011.json"
path.write_text(json.dumps(record,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
status_path = root / "docs/hardware_20261009.json"
status = json.loads(status_path.read_text(encoding="utf-8-sig"))
status.update(record,last_update_utc=stamp,current_temporary_image=image,current_temporary_image_sha256=digest,
    bitstream_sha256=digest,latest_camera_live_state=str(path.relative_to(root)),actual_camera_display_accepted=False,
    capture_result="Qualified clean a4 image Program/Verify passed; prior actual D205 rectification saved; waiting full clean-image recording.")
status_path.write_text(json.dumps(status,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print("Recorded clean qualified image; complete-frame evidence kept separate from current boot.")
