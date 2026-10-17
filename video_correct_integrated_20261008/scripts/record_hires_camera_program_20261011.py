"""Save the new actually programmed resolution, preserving the proven fallback."""
import argparse
from datetime import datetime,timezone
from pathlib import Path
import hashlib
import json

parser=argparse.ArgumentParser()
parser.add_argument("program_log",type=Path)
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
hw=root/"results/hardware_20261009"
log=args.program_log.resolve()
assert log.parent==hw
text=log.read_text(encoding="utf-8-sig",errors="replace")
image="release/ddr_camera_hires_20261011/video_correct_ddr_top.sbit"
assert (root/image).as_posix() in text
assert "COMMAND[Program] execute successfully" in text and "COMMAND[Verify] execute successfully" in text
assert not any(t in text for t in ["execute fail","exec failed","Fail to compare","** Error"])
digest=hashlib.sha256((root/image).read_bytes()).hexdigest()
assert digest=="7aed1ed5af2d32994a620f7bd3f198253365ceeccd967528daa6694e52dac2e0"
record={"recorded_at_utc":datetime.now(timezone.utc).isoformat(),"current_image":image,"current_image_sha256":digest,
    "program_log":str(log.relative_to(root)),"program_log_sha256":hashlib.sha256(log.read_bytes()).hexdigest(),
    "program_verify_passed":True,"flash_modified":False,"phase":"Higher-detail real camera correction verification",
    "source_sampling":[960,540],"processed_output":[640,904],"hdmi_output":[1920,1080],"scale":1,
    "display_window":{"x":640,"y":88,"width":640,"height":904},"diagnostic_grid_present":False,
    "project":"diagnostics/ddr_camera_hires_20261011/results/ddr_camera_hires.pds",
    "source_snapshot":"release/ddr_camera_hires_20261011/source_snapshot.zip",
    "download_entry":"下载高清校正工程.cmd",
    "previous_verified_baseline":"results/hardware_20261009/working_clean_baseline_verified_20261011.json",
    "baseline_restore_entry":"下载相机校正_重连版.cmd",
    "actual_camera_correction_accepted":False,"actual_camera_display_accepted":False,
    "actual_camera_display_accepted_for_current_image":False,"clarity_accepted":False,"clarity_improvement_accepted":False,
    "current_boot_ddr_bist_observed":False,"current_receiver_probe_decoded":False,"current_valid_camera_width_height_measured":False,
    "successful_result_count":None,"capture_bad_count":None,"current_failed_stage":None,
    "algorithm_update_fps_measured":False,"long_term_camera_display_verified":False,
    "computer_use_paused_by_user":True,"original_A_B_C_modified":False,"original_target_modified":False,
    "pending":"Manual OBS source refresh and real large-marker target recording in same fixed camera pose. Verify full page/detail/no missing rows, blackouts or flicker. Keep baseline available.",
    "qualification_limit":"Six simulation checks and timing pass; actual high-detail output and update speed must be measured after this programming."}
path=hw/"hires_camera_state_20261011.json"
path.write_text(json.dumps(record,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
status_path=root/"docs/hardware_20261009.json"
status=json.loads(status_path.read_text(encoding="utf-8-sig"))
status.update(record,current_temporary_image=image,current_temporary_image_sha256=digest,bitstream_sha256=digest,
    last_update_utc=record["recorded_at_utc"],latest_camera_live_state=str(path.relative_to(root)),
    capture_result="High-detail 960x540 source / 640x904 result Program/Verify passed; previous 320x452 full optical correction retained as verified fallback; actual new output pending.")
status_path.write_text(json.dumps(status,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print("Recorded high-detail programming and preserved the physically verified baseline.")
