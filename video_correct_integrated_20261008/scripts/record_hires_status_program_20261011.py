"""Record real D206 Program/Verify and reset observations for this new boot."""
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
assert log.parent==hw and log.name.startswith("program_ddr_camera_hires_status_")
image="release/ddr_camera_hires_status_20261011/video_correct_ddr_top.sbit"
qualification=json.loads((R/"release/ddr_camera_hires_status_20261011/build_qualification.json").read_text(encoding="utf-8-sig"))
digest=hashlib.sha256((R/image).read_bytes()).hexdigest()
assert qualification["simulations_passed"] and qualification["timing_passed"]
assert qualification["files"]["video_correct_ddr_top.sbit"]==digest
text=log.read_text(encoding="utf-8-sig",errors="replace")
assert (R/image).as_posix() in text
assert "COMMAND[Program] execute successfully" in text and "COMMAND[Verify] execute successfully" in text
assert not any(t in text for t in ["execute fail","exec failed","Fail to compare","** Error"])
record={"recorded_at_utc":datetime.now(timezone.utc).isoformat(),"current_image":image,"current_image_sha256":digest,
    "program_log":str(log.relative_to(R)),"program_log_sha256":hashlib.sha256(log.read_bytes()).hexdigest(),
    "program_verify_passed":True,"flash_modified":False,"phase":"Measure actual high-detail DDR row-fetch deadline",
    "source_sampling":[960,540],"processed_output":[640,904],"hdmi_output":[1920,1080],"scale":1,
    "display_window":{"x":640,"y":88,"width":640,"height":904},"diagnostic_grid_present":True,"diagnostic_signature":"D206",
    "diagnostic_fields":"Physical DDR/RX/processor/marker state plus last/max row-fetch UI cycles, row count/index/beat.",
    "project":"diagnostics/ddr_camera_hires_status_20261011/results/ddr_camera_hires_status.pds",
    "source_snapshot":"release/ddr_camera_hires_status_20261011/source_snapshot.zip",
    "download_entry":"下载高清校正诊断.cmd",
    "previous_verified_baseline":"results/hardware_20261009/working_clean_baseline_verified_20261011.json",
    "baseline_restore_entry":"下载相机校正_重连版.cmd",
    "previous_high_detail_failure":"results/hardware_20261009/hires_display_failure_20261011_211430.json",
    "actual_camera_correction_accepted":False,"actual_camera_display_accepted":False,
    "actual_camera_display_accepted_for_current_image":False,"clarity_accepted":False,"clarity_improvement_accepted":False,
    "current_boot_ddr_bist_observed":False,"current_receiver_probe_decoded":False,"current_valid_camera_width_height_measured":False,
    "successful_result_count":None,"capture_bad_count":None,"current_failed_stage":None,
    "algorithm_update_fps_measured":False,"long_term_camera_display_verified":False,
    "computer_use_paused_by_user":True,"original_A_B_C_modified":False,"original_target_modified":False,
    "pending":"Manual OBS deactivate/reactivate, record actual large-marker target for about 20 seconds to read D206, no KEY0 or HDMI recabling.",
    "qualification_limit":"Eight simulations and PDS timing pass; diagnosed high-detail scanout must still be verified on the board."}
path=hw/"hires_status_state_20261011.json"
path.write_text(json.dumps(record,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
main_path=R/"docs/hardware_20261009.json"
main=json.loads(main_path.read_text(encoding="utf-8-sig"))
main.update(record,current_temporary_image=image,current_temporary_image_sha256=digest,bitstream_sha256=digest,
    last_update_utc=record["recorded_at_utc"],latest_camera_live_state=str(path.relative_to(R)),
    capture_result="D206 high-detail diagnostic Program/Verify passed; measure row-fetch deadline after prior high image displayed only top strip. Proven full optical baseline retained.")
main_path.write_text(json.dumps(main,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print(json.dumps({"current_image":image,"sha256":digest,"state":str(path.relative_to(R))},ensure_ascii=False,indent=2))
