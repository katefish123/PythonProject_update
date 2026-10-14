"""Attribute the existing bounded recording probe to the actually programmed image."""
from pathlib import Path
from datetime import datetime, timezone
import json
import hashlib

R=Path(__file__).resolve().parents[1]
hw=R/'results/hardware_20261009'
p=hw/'prefetch_flicker_20261012_230649/probe.json'
probe=json.loads(p.read_text(encoding='utf-8-sig'))
state_path=hw/'prefetch_camera_state_20261012.json'
state=json.loads(state_path.read_text(encoding='utf-8-sig'))
assert state['current_image']==probe['current_image']
assert state['current_image_sha256']==probe['image_sha256']
assert hashlib.sha256((R/state['current_image']).read_bytes()).hexdigest()==probe['image_sha256']
assert state['program_verify_passed']
record={
    'recorded_at_utc':datetime.now(timezone.utc).isoformat(),
    'current_image':probe['current_image'],'image_sha256':probe['image_sha256'],
    'program_log':probe['program_log'],'original_video':probe['original_video'],
    'original_bytes':probe['original_bytes'],'original_sha256':probe['original_sha256'],
    'duration_encoded_seconds':probe['duration_encoded_seconds'],
    'bounded_probe':str(p.relative_to(R)),
    'full_page_observed':True,'stable_picture_accepted':False,
    'user_report':'Full corrected rectangle; slightly improved letters; flickering.',
    'visual_observation':'Saved real video samples show complete upright page and intermittently only its top thin strip. Native vertical row probe confirms frequent dark missing rows in the first75s and last25s.',
    'clarity_improvement_measured':False,'algorithm_update_fps_measured':False,
    'cause_confirmed':False,
    'pending':'Independent display transaction continuity repair and bounded contention regression. No new recording needed to diagnose current failure.',
    'original_video_modified':False,'original_A_B_C_modified':False,
}
receipt=hw/'prefetch_display_flicker_verified_20261013.json'
receipt.write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
updates=dict(actual_camera_correction_accepted=False,actual_camera_display_accepted=False,
    actual_camera_display_accepted_for_current_image=False,short_recording_stable_picture_accepted=False,
    full_corrected_page_observed_for_current_image=True,current_failed_stage='Intermittent display missing rows',
    latest_flicker_evidence=str(receipt.relative_to(R)),pending=record['pending'])
state.update(updates)
state_path.write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
main_path=R/'docs/hardware_20261009.json'
main=json.loads(main_path.read_text(encoding='utf-8-sig'))
assert main['current_image_sha256']==probe['image_sha256']
main.update(updates,last_update_utc=record['recorded_at_utc'],capture_result='Current prefetch image produces full optical correction but intermittently loses displayed rows; stability acceptance failed. Existing recording sufficient.')
main_path.write_text(json.dumps(main,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(receipt)
