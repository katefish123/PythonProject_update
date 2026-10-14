"""Keep yesterday's optical recovery historical and today's reprogramming separate."""
from pathlib import Path
from datetime import datetime,timezone
import argparse,hashlib,json,shutil
ap=argparse.ArgumentParser()
ap.add_argument('program_log',type=Path)
args=ap.parse_args()
R=Path(__file__).resolve().parents[1]
hw=R/'results/hardware_20261009'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
state_path=hw/'rowtrain_camera_state_20261013.json'
state=json.loads(state_path.read_text(encoding='utf-8-sig'))
old_program=json.loads((hw/'rowtrain_coldboot_program_20261013_004921.json').read_text(encoding='utf-8-sig'))
assert old_program['user_reported_board_power_off_then_on'] and old_program['program_verify_passed']
assert sha(R/old_program['program_log'])==old_program['program_log_sha256']
probes=[]
for tag in ['005702','005755']:
    p=hw/f'rowtrain_probe_20261013_{tag}/probe.json'
    probe=json.loads(p.read_text(encoding='utf-8-sig'))
    assert probe['image_sha256']==old_program['image_sha256']
    assert probe['program_log']==old_program['program_log']
    original=Path(probe['original_video'])
    assert sha(original)==probe['original_sha256']
    saved=hw/f'rowtrain_coldboot_camera_20261013_{tag}.mp4'
    if saved.exists():assert sha(saved)==probe['original_sha256']
    else:shutil.copyfile(original,saved)
    probes.append((p,probe,saved))
page_probe=probes[1][1]
metrics=page_probe['spans'][0]['metrics']
start=next(i for i,m in enumerate(metrics) if m['roi_mean']>160)
after=metrics[start:]
assert start==141 and len(after)==1005
assert all(m['dark_rows']==0 and m['roi_mean']>160 for m in after)
# Visually checked saved real contact sheets: first clip only startup bars;
# second contains the complete upright white page with all four corners/text.
now=datetime.now(timezone.utc).isoformat()
recovery={'verified_at_utc':now,'image_sha256':old_program['image_sha256'],
    'program_log':old_program['program_log'],'program_log_sha256':old_program['program_log_sha256'],
    'board_power_cycle_reported_by_user':True,'same_image_reprogrammed':True,
    'user_report':'Corrected image recovered, stable throughout, recordings stopped.',
    'cold_boot_picture_recovery_verified':True,'full_corrected_page_visually_checked':True,
    'analyzed_page_frames':len(after),'analyzed_page_seconds':len(after)/30,
    'first_page_encoded_seconds_estimate':start/30,'missing_dark_rows_after_page':0,
    'recordings':[{'original':p['original_video'],'sha256':p['original_sha256'],'encoded_seconds':p['duration_encoded_seconds'],'probe':str(path.relative_to(R)),'preserved_video':str(saved.relative_to(R))} for path,p,saved in probes],
    'startup_clip_only_bars':True,'startup_black_frames_before_any_page':18,
    'continuous_two_minute_recording_verified':False,'long_term_camera_display_verified':False,
    'algorithm_update_fps_measured':False,'flash_modified':False,
    'scope':'Previous power cycle recovery plus ~33.5s complete corrected page in actual recording. The two files do not contain two continuous minutes of corrected page. Startup-only bars/black excluded from page stability; no change to earlier evidence.'}
receipt_path=hw/'rowtrain_coldboot_camera_verified_20261013_005755.json'
receipt_path.write_text(json.dumps(recovery,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
log=args.program_log.resolve()
assert log.parent==hw and log==max(hw.glob('program_*.log'),key=lambda p:p.stat().st_mtime)
assert log.name.startswith('program_ddr_camera_hires_rowtrain_') and log!=R/old_program['program_log']
image=R/state['current_image']
assert sha(image)==state['current_image_sha256']==old_program['image_sha256']
text=log.read_text(encoding='utf-8-sig',errors='replace')
assert image.as_posix() in text
assert 'COMMAND[Program] execute successfully' in text and 'COMMAND[Verify] execute successfully' in text
assert not any(t in text for t in ['execute fail','exec failed','Fail to compare','** Error'])
updates=dict(program_log=str(log.relative_to(R)),program_log_sha256=sha(log),program_verify_passed=True,
    latest_program_at_utc=now,paused_by_user=False,
    previous_coldboot_optical_evidence=str(receipt_path.relative_to(R)),
    same_image_previous_coldboot_recovery_verified=True,
    cold_boot_recovery_verified_for_current_image=True,
    current_boot_optical_picture_verified=False,current_boot_video_analysis=None,current_boot_video_evidence=None,
    current_boot_ddr_bist_observed=False,current_receiver_probe_decoded=False,
    current_valid_camera_width_height_measured=False,long_term_camera_display_verified=False,
    phase='Same qualified image reprogrammed after disconnected overnight; current optical recovery and actual update-rate check pending',
    pending='Keep same bitstream and HDMI chain. Fresh current-boot optical counter target recording will check visible recovery and actual result updates; previous cold-boot evidence retained.',
    qualification_limit='Same image14 simulations/timing and short optical/cold-boot recovery confirmed in previous recordings. Current boot picture, long run and actual algorithm FPS remain unverified.')
state.update(updates)
state_path.write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
main_path=R/'docs/hardware_20261009.json'
main=json.loads(main_path.read_text(encoding='utf-8-sig'))
assert main['current_image_sha256']==state['current_image_sha256']
main.update(updates,last_update_utc=now,capture_result="Earlier power-cycle recovery verified from actual ~33.5s corrected page; today's same image Program/Verify passed, fresh current-boot optical/performance check pending.")
main_path.write_text(json.dumps(main,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
guide=R/'docs/当前工程入口_20261011.md'
prefix=f'''## 2026-10-13 重新接续

昨晚断电后重新下载同一程序的恢复录像已核对：有效完整校正画面约33.5秒，未检测到缺行或黑屏。按实际录像接受恢复，不计作两分钟连续稳定性测试。证据：results/hardware_20261009/rowtrain_coldboot_camera_verified_20261013_005755.json。

今天用户报告昨晚全部拔掉断电，当前同一eb06c8f9程序已重新下载回读通过；日志：{updates['program_log']}。本次上电画面尚待新录像，不能借用昨晚恢复结果代替。下一步用独立变化计数测试图检查真实更新速度，原静态测试图仍保留。

以下为先前验收记录。

'''
guide.write_text(prefix+guide.read_text(encoding='utf-8-sig'),encoding='utf-8')
print(json.dumps({'historical_recovery':str(receipt_path),'today_program_log':updates['program_log'],'same_image':state['current_image_sha256']},ensure_ascii=False,indent=2))
