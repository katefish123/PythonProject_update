"""Preserve actual short-run optical correction; never infer long-run stability/FPS."""
from datetime import datetime,timezone
from pathlib import Path
import hashlib,json,shutil,re
R=Path(__file__).resolve().parents[1]
hw=R/'results/hardware_20261009'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
state_path=hw/'rowtrain_camera_state_20261013.json'
state=json.loads(state_path.read_text(encoding='utf-8-sig'))
probe_path=hw/'rowtrain_probe_20261013_003121/probe.json'
probe=json.loads(probe_path.read_text(encoding='utf-8-sig'))
assert probe['image_sha256']==state['current_image_sha256']=='eb06c8f9645665111b339e2ea305549a107830275d50f7625245b163b371d987'
assert state['program_verify_passed'] and sha(R/state['current_image'])==probe['image_sha256']
program=R/state['program_log']
assert program==max(hw.glob('program_*.log'),key=lambda p:p.stat().st_mtime)
assert sha(program)==state['program_log_sha256']
video=Path(probe['original_video'])
assert video.name=='2026-10-13 00-31-21.mp4' and sha(video)==probe['original_sha256']
assert video.stat().st_size==probe['original_bytes']==25347429
metrics=probe['spans'][0]['metrics']
assert len(metrics)==1011
start=next(i for i,m in enumerate(metrics) if m['roi_mean']>160)
assert start==229
after=metrics[start:]
assert len(after)==782 and all(m['dark_rows']==0 and m['roi_mean']>160 for m in after)
# Actual saved full-size sample and contact sheet were visually inspected in
# this turn: startup bars, an initially defocused result, then complete paper,
# its four colored corners, title/grid/text. No fabricated diagnostic picture.
assert len(probe['sample_frames'])==9
for sample in probe['sample_frames']:assert (R/sample['frame']).is_file()
obs_logs=R/'tools/obs-studio/portable/config/obs-studio/logs'
candidates=[p for p in obs_logs.glob('*.txt') if video.name in p.read_text(encoding='utf-8-sig',errors='replace')]
assert len(candidates)==1
obs=candidates[0]
text=obs.read_text(encoding='utf-8-sig',errors='replace')
tail=text[text.index('00:31:19.799:'):]
assert 'format: NV12' in tail and 'resolution: 1920x1080' in tail and 'fps: 30.00' in tail
assert '==== Recording Stop' in tail and 'File output complete' in tail
assert 'Total frames output: 1014' in tail
assert not re.search(r'error|failed|decode failure',tail,re.I)
saved=hw/'rowtrain_corrected_camera_20261013_003121.mp4'
if saved.exists():assert sha(saved)==probe['original_sha256']
else:shutil.copyfile(video,saved)
assert sha(saved)==probe['original_sha256']
obs_copy=hw/'rowtrain_camera_obs_20261013_003121.log'
obs_copy.write_bytes(obs.read_bytes())
now=datetime.now(timezone.utc).isoformat()
record={
    'verified_at_utc':now,'current_image':state['current_image'],'image_sha256':state['current_image_sha256'],
    'program_log':state['program_log'],'program_log_sha256':state['program_log_sha256'],'program_verify_passed':True,
    'physical_route':'R50 -> FPGA HDMI-IN -> FPGA HDMI-OUT -> VC-002Pro -> PC USB',
    'user_report':'Complete rectangular corrected picture, stable without flicker; recording stopped.',
    'original_video':str(video),'original_bytes':probe['original_bytes'],'video_sha256':probe['original_sha256'],
    'preserved_video':str(saved.relative_to(R)),'original_video_modified':False,
    'obs_log':str(obs_copy.relative_to(R)),'obs_log_sha256':sha(obs_copy),
    'obs_recording_finalized':True,'obs_encoded_frames_reported':1014,
    'probe':str(probe_path.relative_to(R)),'probe_sha256':sha(probe_path),
    'encoded_duration_seconds':33.73,'analyzed_decoded_frames':1011,
    'first_page_frame_estimate':start,'first_page_encoded_seconds_estimate':round(start/30,4),
    'analyzed_page_frames':len(after),'analyzed_page_duration_seconds':round(len(after)/30,4),
    'missing_dark_rows_after_page':0,'whole_dark_frames_after_page':0,'fallback_frames_after_page':0,
    'full_corrected_page_visually_checked':True,
    'actual_camera_correction_accepted':True,'short_recording_stable_picture_accepted':True,
    'clarity_observation':'Native saved last frame contains readable title and labels; residual optical moire/softness remains. Same-camera quantitative sharpness comparison not performed.',
    'clarity_improvement_measured':False,'algorithm_update_fps_measured':False,'long_term_camera_display_verified':False,
    'cold_boot_recovery_verified_for_this_image':False,'flash_modified':False,
    'scope':'Current optical source-to-FPGA-to-card short run only. Startup bars excluded from page stability interval; recorded/encoded frames are not independent algorithm updates.',
    'baseline_retained':'results/hardware_20261009/baseline_recovered_verified_20261012.json',
    'original_A_B_C_modified':False,'original_target_modified':False,
}
receipt=hw/'rowtrain_camera_verified_20261013_003121.json'
receipt.write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
updates=dict(actual_camera_correction_accepted=True,actual_camera_display_accepted=True,
    actual_camera_display_accepted_for_current_image=True,full_corrected_page_observed_for_current_image=True,
    short_recording_stable_picture_accepted=True,current_failed_stage=None,
    latest_camera_verified_evidence=str(receipt.relative_to(R)),latest_video_analysis=str(probe_path.relative_to(R)),
    latest_original_video=str(video),latest_video_sha256=probe['original_sha256'],latest_preserved_video=str(saved.relative_to(R)),
    algorithm_update_fps_measured=False,long_term_camera_display_verified=False,cold_boot_recovery_verified_for_current_image=False,
    clarity_improvement_accepted=False,
    pending='Current high-detail full-frame/no-flicker short test accepted and preserved. Keep this release as the working version. Remaining whole-project acceptance: longer run, power-cycle recovery and actual algorithm update performance; comparative optical sharpness unmeasured.',
    qualification_limit='Fourteen simulations, final timing, real Program/Verify and uniquely attributed actual optical recording passed for this short run. Do not extend to long-term stability, cold boot, quantified clarity or update FPS.')
state.update(updates,last_verified_at_utc=now)
state_path.write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
main_path=R/'docs/hardware_20261009.json'
main=json.loads(main_path.read_text(encoding='utf-8-sig'))
assert main['current_image_sha256']==state['current_image_sha256']
main.update(updates,last_update_utc=now,capture_result='Current row-train640x904 actual optical correction verified: complete page, all corners, no missing rows/blackout/fallback in782 analyzed page frames (~26.1s). Long-run/cold-boot/FPS not yet verified.')
main_path.write_text(json.dumps(main,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'evidence':str(receipt),'analyzed_page_seconds':record['analyzed_page_duration_seconds'],'video_sha256':probe['original_sha256']},ensure_ascii=False,indent=2))
