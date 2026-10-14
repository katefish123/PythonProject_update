"""Record only a real successful row-train Program/Verify, clearing old acceptance."""
from pathlib import Path
from datetime import datetime,timezone
import argparse,hashlib,json
ap=argparse.ArgumentParser()
ap.add_argument('program_log',type=Path)
args=ap.parse_args()
R=Path(__file__).resolve().parents[1]
hw=R/'results/hardware_20261009'
log=args.program_log.resolve()
assert log.parent==hw and log.name.startswith('program_ddr_camera_hires_rowtrain_')
assert log==max(hw.glob('program_*.log'),key=lambda p:p.stat().st_mtime)
image='release/ddr_camera_hires_rowtrain_20261013/video_correct_ddr_top.sbit'
q=json.loads((R/'release/ddr_camera_hires_rowtrain_20261013/build_qualification.json').read_text(encoding='utf-8-sig'))
digest=hashlib.sha256((R/image).read_bytes()).hexdigest()
assert digest==q['files']['video_correct_ddr_top.sbit'] and q['simulations_passed'] and q['timing_passed']
s=log.read_text(encoding='utf-8-sig',errors='replace')
assert (R/image).as_posix() in s
assert 'COMMAND[Program] execute successfully' in s and 'COMMAND[Verify] execute successfully' in s
assert not any(x in s for x in ['execute fail','exec failed','Fail to compare','** Error'])
record=json.loads((hw/'prefetch_camera_state_20261012.json').read_text(encoding='utf-8-sig'))
record.update(recorded_at_utc=datetime.now(timezone.utc).isoformat(),current_image=image,current_image_sha256=digest,
    program_log=str(log.relative_to(R)),program_log_sha256=hashlib.sha256(log.read_bytes()).hexdigest(),
    program_verify_passed=True,flash_modified=False,paused_by_user=False,
    phase='Actual high-detail camera check after continuous row request repair',display_row_train=True,
    project='diagnostics/ddr_camera_hires_rowtrain_20261013/results/ddr_camera_hires_rowtrain.pds',
    source_snapshot='release/ddr_camera_hires_rowtrain_20261013/source_snapshot.zip',download_entry='下载高清校正_行读取修复版.cmd',
    previous_high_detail_failure='results/hardware_20261009/prefetch_display_flicker_verified_20261013.json',
    actual_camera_correction_accepted=False,actual_camera_display_accepted=False,actual_camera_display_accepted_for_current_image=False,
    full_corrected_page_observed_for_current_image=False,clarity_accepted=False,clarity_improvement_accepted=False,
    short_recording_stable_picture_accepted=False,long_term_camera_display_verified=False,current_boot_ddr_bist_observed=False,
    current_receiver_probe_decoded=False,current_valid_camera_width_height_measured=False,successful_result_count=None,
    capture_bad_count=None,current_failed_stage=None,algorithm_update_fps_measured=False,latest_flicker_evidence=None,
    latest_video_analysis=None,latest_original_video=None,latest_video_sha256=None,
    pending='Manual source reactivation, same large-marker target; short15-20s recording, then Esc and STOP RECORDING. No new analysis recording needed for previous failure.',
    qualification_limit='Fourteen saved checks, identical old/new contention comparison, PDS timing and actual Program/Verify. Physical picture stability still needs the new image recording.')
state=hw/'rowtrain_camera_state_20261013.json'
state.write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
main_path=R/'docs/hardware_20261009.json'
main=json.loads(main_path.read_text(encoding='utf-8-sig'))
main.update(record,last_update_utc=record['recorded_at_utc'],current_temporary_image=image,current_temporary_image_sha256=digest,
    bitstream_sha256=digest,latest_camera_live_state=str(state.relative_to(R)),
    capture_result='Row-train image Program/Verify passed. Current physical output pending; all earlier acceptance remains attached to its original image only.')
main_path.write_text(json.dumps(main,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'state':str(state),'image':image,'sha256':digest},ensure_ascii=False,indent=2))
