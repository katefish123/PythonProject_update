"""Separate first-picture observation, input loss, and unaccepted recovery build."""
from pathlib import Path
from datetime import datetime,timezone
import hashlib
import json

R=Path(__file__).resolve().parents[1]
H=R/'results/hardware_20261009'
image='release/camera_live_bram_reconnect_20261010/camera_live_bram_top.sbit'
digest=hashlib.sha256((R/image).read_bytes()).hexdigest()
assert digest=='be1a72cade3008e25cff3f6925bf6347fea8211da6e5447fdd82ef137e7f5212'
program=H/'program_camera_live_bram_reconnect_20261010_210414.log'
text=program.read_text(encoding='utf-8-sig',errors='replace')
assert 'COMMAND[Program] execute successfully' in text and 'COMMAND[Verify] execute successfully' in text
assert not any(t in text for t in ['execute fail','exec failed','Fail to compare'])
qualification=json.loads((R/'release/camera_live_bram_reconnect_20261010/build_qualification.json').read_text(encoding='utf-8'))
for name,expected in qualification['files'].items():
    assert hashlib.sha256((R/'release/camera_live_bram_reconnect_20261010'/name).read_bytes()).hexdigest()==expected,name
loss=json.loads((H/'camera_bram_after_live_input_loss_20261010.json').read_text(encoding='utf-8'))
assert not loss['frame_valid'] and loss['frequency_registers']=='0x00000000'
record={
    'utc':datetime.now(timezone.utc).isoformat(),'current_image':image,'current_image_sha256':digest,
    'program_verify_passed':True,'program_log':str(program.relative_to(R)),
    'original_preview_retained':'release/camera_live_bram_20261010',
    'restore_entry':'恢复相机预览.cmd',
    'first_raw_camera_image_seen':True,
    'first_image_evidence':'User confirmed after R50 restart; assistant observed real camera view filming the computer display in OBS at 20:41. The initial window snapshot was not saved as a local file.',
    'first_image_version_sha256':'00f3a1aec7c75893ba2ecccb09578379512f8f8d92b6a2d765bc53cea3cc1816',
    'continuous_camera_display_verified':False,
    'subsequent_input_loss_probe':loss,
    'subsequent_input_loss_recording':'results/hardware_20261009/camera_bram_input_loss_20261010.mp4',
    'recording_contains':'Diagnostic grid after input loss, not a successful live camera recording',
    'receiver_reconnect_failure_reproduced':True,
    'receiver_reconnect_simulations_passed':True,'reconnect_candidate_timing_passed':True,
    'reconnect_candidate_hardware_display_accepted':False,
    'obs_recording_stopped':True,'obs_streaming_started':False,
    'window_observation_blocked':'Two activation attempts failed: failed to activate captured window',
    'camera_auto_power_off_setting_confirmed':False,
    'pending':'User confirm unlocked PC and foreground OBS; check R50 camera+monitor HDMI mode and disable auto power off; verify live recovery and continuity',
    'esc_behavior_modified':False,'original_A_B_C_changed_this_stage':False,'flash_modified':False,
}
(H/'camera_reconnect_state_20261010.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
status_file=R/'docs/hardware_20261009.json'
status=json.loads(status_file.read_text(encoding='utf-8-sig'))
status.update(last_update_utc=record['utc'],current_temporary_image=image,
              current_temporary_image_sha256=digest,bitstream_sha256=digest,
              first_raw_camera_image_seen=True,continuous_camera_display_verified=False,
              actual_camera_display_accepted=False,actual_camera_correction_accepted=False,
              raw_bram_reconnect_programmed=True,raw_bram_reconnect_verify_passed=True,
              raw_bram_reconnect_sha256=digest,
              capture_result='First real camera image observed on original BRAM preview, then input loss; recovery candidate programmed/verified but display check pending',
              pending=record['pending'],paused_by_user=False,
              latest_camera_live_state='results/hardware_20261009/camera_reconnect_state_20261010.json')
status_file.write_text(json.dumps(status,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Saved first-picture observation, subsequent input loss, tested reconnect fix and verified current image. Continuous display is still pending.')
