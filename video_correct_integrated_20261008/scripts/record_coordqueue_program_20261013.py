"""Record a real qualified new-image Program/Verify; never reuse baseline media."""
from pathlib import Path
from datetime import datetime,timezone
import argparse,hashlib,json
ap=argparse.ArgumentParser()
ap.add_argument('program_log',type=Path)
args=ap.parse_args()
R=Path(__file__).resolve().parents[1]
hw=R/'results/hardware_20261009'
log=args.program_log.resolve()
assert log.parent==hw and log.name.startswith('program_ddr_camera_coordqueue_')
assert log==max(hw.glob('program_*.log'),key=lambda p:p.stat().st_mtime)
image='release/ddr_camera_coordqueue_20261013/video_correct_ddr_top.sbit'
q=json.loads((R/'release/ddr_camera_coordqueue_20261013/build_qualification.json').read_text(encoding='utf-8-sig'))
digest=hashlib.sha256((R/image).read_bytes()).hexdigest()
assert digest==q['files']['video_correct_ddr_top.sbit']=='1be0d8aeb90745a560089912d6c221a91962247926d82cb159ac0c335b3ac996'
assert q['simulations_passed'] and q['timing_passed']
s=log.read_text(encoding='utf-8-sig',errors='replace')
assert (R/image).as_posix() in s
assert 'COMMAND[Program] execute successfully' in s and 'COMMAND[Verify] execute successfully' in s
assert not any(t in s for t in ['execute fail','exec failed','Fail to compare','** Error'])
record=json.loads((hw/'rowtrain_camera_state_20261013.json').read_text(encoding='utf-8-sig'))
record.update(recorded_at_utc=datetime.now(timezone.utc).isoformat(),current_image=image,current_image_sha256=digest,
    program_log=str(log.relative_to(R)),program_log_sha256=hashlib.sha256(log.read_bytes()).hexdigest(),
    program_verify_passed=True,flash_modified=False,current_program_resident=True,board_power_reported_off=False,
    phase='Qualified coordinate lookahead image programmed; fresh camera, actual update rate and temperature confirmation pending',
    project='diagnostics/ddr_camera_coordqueue_20261013/results/ddr_camera_coordqueue.pds',
    source_snapshot='release/ddr_camera_coordqueue_20261013/source_snapshot.zip',download_entry='下载高清校正_坐标预计算版.cmd',
    baseline_restore_entry='下载高清校正_行读取修复版.cmd',coordinate_lookahead_credits=16,
    previous_verified_baseline='results/hardware_20261009/rowtrain_actual_update_rate_verified_20261013.json',
    actual_camera_correction_accepted=False,actual_camera_display_accepted=False,actual_camera_display_accepted_for_current_image=False,
    full_corrected_page_observed_for_current_image=False,short_recording_stable_picture_accepted=False,
    observed_corrected_output_update_hz=None,observed_mean_inter_update_seconds=None,algorithm_update_fps_measured=False,
    latest_performance_evidence=None,latest_video_analysis=None,latest_original_video=None,latest_video_sha256=None,latest_preserved_video=None,
    current_boot_optical_picture_verified=False,current_boot_video_analysis=None,current_boot_video_evidence=None,
    current_boot_ddr_bist_observed=False,current_receiver_probe_decoded=False,current_valid_camera_width_height_measured=False,
    cold_boot_recovery_verified_for_current_image=False,long_term_camera_display_verified=False,
    hardware_speedup_accepted=False,current_failed_stage=None,
    pending='Fresh30s optical counter video under confirmed temperature monitoring; reactivate OBS manually, keep all four markers visible, then Esc/Stop Recording. Compare same geometry/quality and real observed rate to0.85Hz baseline.',
    qualification_limit='Fifteen simulations and final timing passed.2.03x modeled cycle improvement is not a measured new board performance result.')
state=hw/'coordqueue_camera_state_20261013.json'
state.write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
main_path=R/'docs/hardware_20261009.json'
main=json.loads(main_path.read_text(encoding='utf-8-sig'))
main.update(record,last_update_utc=record['recorded_at_utc'],current_temporary_image=image,current_temporary_image_sha256=digest,
    bitstream_sha256=digest,latest_camera_live_state=str(state.relative_to(R)),
    capture_result='New coordinate lookahead Program/Verify passed; all actual current-image picture/performance acceptance reset, baseline proof retained.')
main_path.write_text(json.dumps(main,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'state':str(state),'image':image,'sha256':digest,'actual_picture_pending':True},ensure_ascii=False,indent=2))
