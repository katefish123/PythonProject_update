"""Record actual vendor verification, preserving earlier failed evidence."""
from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,re
R=Path(__file__).resolve().parents[1]
H=R/'results/hardware_20261009'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
logs=['program_runtime_after_reseat_20261010.log','program_rx_first_shutdown_1mhz_20261010.log',
      'program_ddr_shutdown_1mhz_20261010.log']
verified={}
for name in logs:
    p=H/name
    text=p.read_text(encoding='utf-8-sig',errors='replace')
    assert 'COMMAND[Program] execute successfully' in text
    assert 'COMMAND[Verify] execute successfully' in text
    assert not re.search(r'execute fail|exec failed|Fail to compare',text)
    assert 'program 1 -readback 1' in text
    verified[name]={'program_and_verify_passed':True,'sha256':sha(p)}
record={'recorded_at_utc':datetime.now(timezone.utc).isoformat(),'verified_logs':verified,
 'jtag_frequency':'1MHz','program_property':1,'readback_property':1,
 'current_board_image':'release/ddr_startup_fixed_20261009/video_correct_ddr_top.sbit',
 'current_board_sha256':'85c11bebe47b97621619daf1fbf0f04e33fa270f5444e481c8280ee2d5ac2875',
 'actual_camera_correction_accepted':False,'current_boot_ddr_bist_observed':False,
 'target_display_visually_verified':False,'obs_device_id_refreshed':True,
 'pending':'User screen/unlock confirmation, KEY0 logic restart and camera view; then real four-marker capture test'}
(H/'resume_programming_verified_20261010.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
state_path=R/'docs/hardware_20261009.json'
state=json.loads(state_path.read_text(encoding='utf-8-sig'))
state.update(last_update_utc=record['recorded_at_utc'],paused_by_user=False,
 configuration_verify_passed=True,current_main_configuration_verify_passed=True,
 current_temporary_image=record['current_board_image'],current_temporary_image_sha256=record['current_board_sha256'],
 rx_first_resume_verify_passed=True,rx_first_trial_programmed=True,
 main_ddr_resume_program_verify_passed=True,current_boot_ddr_bist_observed=False,
 actual_camera_correction_accepted=False,obs_device_path_needs_refresh=False,
 obs_actual_format='1920x1080 MJPEG 60fps; device-default mode',
 pending=record['pending'])
state_path.write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'vendor_verified_images':3,'current_image':record['current_board_image'],
                  'camera_acceptance_completed':False},ensure_ascii=False,indent=2))
