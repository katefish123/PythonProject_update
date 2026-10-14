"""Record the new actually programmed image without borrowing baseline acceptance."""
import argparse
from datetime import datetime,timezone
from pathlib import Path
import hashlib
import json

parser=argparse.ArgumentParser()
parser.add_argument("program_log",type=Path)
args=parser.parse_args()
R=Path(__file__).resolve().parents[1]
hw=R/"results/hardware_20261009"
log=args.program_log.resolve()
assert log.parent==hw and log.name.startswith("program_ddr_camera_hires_prefetch_")
assert log==max(hw.glob("program_*.log"),key=lambda p:p.stat().st_mtime)
image="release/ddr_camera_hires_prefetch_20261012/video_correct_ddr_top.sbit"
qualification=json.loads((R/"release/ddr_camera_hires_prefetch_20261012/build_qualification.json").read_text(encoding="utf-8-sig"))
digest=hashlib.sha256((R/image).read_bytes()).hexdigest()
assert digest==qualification["files"]["video_correct_ddr_top.sbit"]=="60fb0b53a5c13b2c1adf47539c66bb4426d967effa2e3f2a279a9cac09865f22"
text=log.read_text(encoding="utf-8-sig",errors="replace")
assert (R/image).as_posix() in text
assert "COMMAND[Program] execute successfully" in text and "COMMAND[Verify] execute successfully" in text
assert not any(token in text for token in ["execute fail","exec failed","Fail to compare","** Error"])
record={"recorded_at_utc":datetime.now(timezone.utc).isoformat(),"paused_by_user":False,
 "current_image":image,"current_image_sha256":digest,"program_log":str(log.relative_to(R)),
 "program_log_sha256":hashlib.sha256(log.read_bytes()).hexdigest(),"program_verify_passed":True,"flash_modified":False,
 "phase":"Actual high-detail full-frame/clarity validation after result read-ahead fix",
 "source_sampling":[960,540],"processed_output":[640,904],"hdmi_output":[1920,1080],"scale":1,
 "display_window":{"x":640,"y":88,"width":640,"height":904},"capture_fifo_packets":1024,
 "result_read_ahead_beats":8,"result_read_cache_bytes":256,"diagnostic_grid_present":False,
 "diagnostic_signature":None,"diagnostic_fields":None,
 "project":"diagnostics/ddr_camera_hires_prefetch_20261012/results/ddr_camera_hires_prefetch.pds",
 "source_snapshot":"release/ddr_camera_hires_prefetch_20261012/source_snapshot.zip",
 "download_entry":"下载高清校正_连续读取版.cmd","baseline_restore_entry":"下载相机校正_重连版.cmd",
 "previous_verified_baseline":"results/hardware_20261009/baseline_recovered_verified_20261012.json",
 "previous_high_detail_failure":"results/hardware_20261009/hires_display_failure_20261011_211430.json",
 "physical_route_current":"R50 -> FPGA HDMI-IN -> FPGA HDMI-OUT -> VC-002Pro -> PC USB",
 "actual_camera_correction_accepted":False,"actual_camera_display_accepted":False,
 "actual_camera_display_accepted_for_current_image":False,"clarity_accepted":False,"clarity_improvement_accepted":False,
 "short_recording_stable_picture_accepted":False,"current_boot_ddr_bist_observed":False,
 "current_receiver_probe_decoded":False,"current_valid_camera_width_height_measured":False,
 "successful_result_count":None,"capture_bad_count":None,"current_failed_stage":None,
 "algorithm_update_fps_measured":False,"long_term_camera_display_verified":False,
 "computer_use_paused_by_user":True,"original_A_B_C_modified":False,"original_target_modified":False,
 "pending":"Manually reactivate OBS source, keep camera pose/focus and all HDMI connections; record the same large-marker optical target about30s plus5s after closing. Verify full corrected page, clarity and missing rows/flicker/blackout.",
 "qualification_limit":"Twelve simulation checks and PDS timing passed; actual source/algorithm/display and detail still require uniquely attributed physical media."}
state=hw/"prefetch_camera_state_20261012.json"
state.write_text(json.dumps(record,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
main_path=R/"docs/hardware_20261009.json"
main=json.loads(main_path.read_text(encoding="utf-8-sig"))
main.update(record,last_update_utc=record["recorded_at_utc"],current_temporary_image=image,
 current_temporary_image_sha256=digest,bitstream_sha256=digest,latest_camera_live_state=str(state.relative_to(R)),
 capture_result="New high-detail result prefetch Program/Verify passed; current real picture and clarity unaccepted; baseline recovery media retained.")
main_path.write_text(json.dumps(main,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print(json.dumps({"state":str(state.relative_to(R)),"image":image,"sha256":digest},ensure_ascii=False,indent=2))
