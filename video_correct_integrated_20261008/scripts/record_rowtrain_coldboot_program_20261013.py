"""Record reprogramming after a human power cycle, retaining image-level evidence."""
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
state_path=hw/'rowtrain_camera_state_20261013.json'
state=json.loads(state_path.read_text(encoding='utf-8-sig'))
image=R/state['current_image']
digest=hashlib.sha256(image.read_bytes()).hexdigest()
assert digest==state['current_image_sha256']=='eb06c8f9645665111b339e2ea305549a107830275d50f7625245b163b371d987'
q=json.loads((R/'release/ddr_camera_hires_rowtrain_20261013/build_qualification.json').read_text(encoding='utf-8-sig'))
assert digest==q['files']['video_correct_ddr_top.sbit'] and q['simulations_passed'] and q['timing_passed']
s=log.read_text(encoding='utf-8-sig',errors='replace')
assert image.as_posix() in s
assert 'COMMAND[Program] execute successfully' in s and 'COMMAND[Verify] execute successfully' in s
assert not any(x in s for x in ['execute fail','exec failed','Fail to compare','** Error'])
previous=hw/'rowtrain_camera_verified_20261013_003121.json'
receipt=json.loads(previous.read_text(encoding='utf-8-sig'))
assert receipt['image_sha256']==digest and receipt['short_recording_stable_picture_accepted']
assert log!=R/receipt['program_log']
now=datetime.now(timezone.utc).isoformat()
record={'recorded_at_utc':now,'user_reported_board_power_off_then_on':True,
    'image':state['current_image'],'image_sha256':digest,'same_verified_bitstream':True,
    'program_log':str(log.relative_to(R)),'program_log_sha256':hashlib.sha256(log.read_bytes()).hexdigest(),
    'program_verify_passed':True,'flash_modified':False,
    'previous_short_optical_evidence':str(previous.relative_to(R)),
    'current_boot_optical_picture_verified':False,'cold_boot_picture_recovery_verified':False,
    'pending':'After this actual reprogramming, manually reactivate OBS and film the same target for a longer bounded run, then stop recording. Verify actual optical recovery and missing-row/blackout behavior.',
    'scope':'User-reported physical board power cycle plus real configuration/verify only; prior same-image optical success remains historical and does not validate this boot.'}
record_path=hw/('rowtrain_coldboot_program_'+log.stem.removeprefix('program_ddr_camera_hires_rowtrain_')+'.json')
record_path.write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
updates=dict(program_log=record['program_log'],program_log_sha256=record['program_log_sha256'],program_verify_passed=True,
    latest_program_at_utc=now,latest_coldboot_program=str(record_path.relative_to(R)),
    user_reported_board_power_cycle=True,current_boot_optical_picture_verified=False,
    cold_boot_recovery_verified_for_current_image=False,current_boot_ddr_bist_observed=False,
    current_receiver_probe_decoded=False,current_valid_camera_width_height_measured=False,
    current_boot_video_analysis=None,current_boot_video_evidence=None,
    phase='Same verified row-train image reprogrammed after board power cycle; new boot optical check pending',
    pending=record['pending'])
state.update(updates)
state_path.write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
main_path=R/'docs/hardware_20261009.json'
main=json.loads(main_path.read_text(encoding='utf-8-sig'))
assert main['current_image_sha256']==digest
main.update(updates,last_update_utc=now,capture_result='User power-cycled board; same eb06c8f9 image Program/Verify passed. Prior26s optical acceptance retained for its boot; current boot recovery and longer recording pending.')
main_path.write_text(json.dumps(main,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
guide=R/'docs/当前工程入口_20261011.md'
prefix=f'## 断电恢复检查进行中\n\n用户已将板子断电再上电；同一eb06c8f9程序重新下载回读通过。当前下载日志：{record["program_log"]}。上一轮短测资格属于上一轮上电；本次恢复画面仍待新的实际录像，未沿用上一轮结果。\n\n'
old=guide.read_text(encoding='utf-8-sig')
guide.write_text(prefix+old,encoding='utf-8')
print(json.dumps({'state':str(record_path),'image_sha256':digest,'program_verify_passed':True,'current_boot_picture_pending':True},ensure_ascii=False,indent=2))
