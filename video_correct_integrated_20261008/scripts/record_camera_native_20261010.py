"""Record verified download separately from pending real camera acceptance."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import shutil

R = Path(__file__).resolve().parents[1]
H = R / 'results/hardware_20261009'
image = 'release/camera_live_native_20261010/camera_live_native_top.sbit'
digest = hashlib.sha256((R / image).read_bytes()).hexdigest()
assert digest == '00e696c084513c48465ad22662585d862a7d30cc76efb0c998d70a98bb388b53'
program = H / 'program_camera_live_native_20261010_224110.log'
text = program.read_text(encoding='utf-8-sig', errors='replace')
assert 'COMMAND[Program] execute successfully' in text
assert 'COMMAND[Verify] execute successfully' in text
assert not any(t in text for t in ['execute fail', 'exec failed', 'Fail to compare'])
qualification = json.loads((R / 'release/camera_live_native_20261010/build_qualification.json').read_text())
for name, expected in qualification['files'].items():
    assert hashlib.sha256((R / 'release/camera_live_native_20261010' / name).read_bytes()).hexdigest() == expected, name
record = {
    'utc': datetime.now(timezone.utc).isoformat(), 'current_image': image,
    'current_image_sha256': digest, 'program_verify_passed': True,
    'program_log': str(program.relative_to(R)), 'flash_modified': False,
    'video_path': 'Every real RX RGB888 pixel, HS and DE forwarded through two register stages; VS recovery retained from C',
    'frame_buffer_or_ddr': False, 'downsample_or_upscale': False,
    'config_order': 'TX first; RX continues status polling and has tested 00-to-03 reconnect fix',
    'simulations_passed': True, 'timing_passed': True,
    'camera_settings_user_confirmed': {'HDMI_display': 'Camera + external monitor', 'auto_power_off': 'Disabled'},
    'previous_reconnect_preview_user_reported_recovered': True,
    'pre_upgrade_capture': 'results/hardware_20261009/bram_reconnect_before_hd_upgrade_20261010.png',
    'pre_upgrade_frequency_registers': '0x00000000',
    'board_power_cycle_reported_by_user': True,
    'obs_old_frame_cleared_by_deactivate_reactivate': True,
    'latest_observation': 'Black immediately after reactivating capture; awaiting physical KEY0 and camera live check',
    'actual_camera_display_accepted': False, 'continuous_camera_display_verified': False,
    'actual_camera_correction_accepted': False,
    'pending': 'User KEY0 reset after new download; observe and save actual native camera image, then continuity and four-marker DDR correction',
    'retained_releases': ['release/camera_live_bram_20261010', 'release/camera_live_bram_reconnect_20261010', 'release/ddr_startup_fixed_20261009'],
    'restore_entries': ['恢复相机预览.cmd', '恢复相机预览_重连修正版.cmd', '下载高清相机预览.cmd'],
    'obs_recording_running': False, 'obs_streaming_started': False,
    'original_A_B_C_modified': False, 'esc_behavior_modified': False,
}
(H / 'camera_native_state_20261010.json').write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
state_file = R / 'docs/hardware_20261009.json'
backup = H / 'hardware_status_before_native_20261010.json'
if not backup.exists():
    shutil.copy2(state_file, backup)
status = json.loads(state_file.read_text(encoding='utf-8-sig'))
status.update(last_update_utc=record['utc'], current_temporary_image=image,
              current_temporary_image_sha256=digest, bitstream_sha256=digest,
              current_main_configuration_verify_passed=True,
              latest_camera_live_state='results/hardware_20261009/camera_native_state_20261010.json',
              native_preview_programmed=True, native_preview_configuration_verify_passed=True,
              native_preview_sha256=digest, camera_auto_power_off_setting_confirmed=True,
              capture_result=record['latest_observation'], pending=record['pending'],
              actual_camera_display_accepted=False, continuous_camera_display_verified=False,
              actual_camera_correction_accepted=False, current_boot_ddr_bist_observed=False,
              paused_by_user=False)
state_file.write_text(json.dumps(status, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
prefix = '''## 22:44 高清预览接续

用户确认 R50“相机＋外接监视器”、关闭自动关机后恢复画面，随后告知板子断电，需要重新下载。为改善320×180缩小放大的清晰度，新增独立完整RGB888预览；两整帧逐像素、缺VS回退、真实I²C及两次重连检查全部通过，PDS所有约束满足。`release/camera_live_native_20261010/camera_live_native_top.sbit`（SHA256 `00e696c084513c48465ad22662585d862a7d30cc76efb0c998d70a98bb388b53`）已Program/Verify成功，日志 `program_camera_live_native_20261010_224110.log`。当前CRAM为该版本；未写Flash。

已在OBS关闭并重新激活采集源，清除下载前保留的旧红绿格；刚激活时黑屏，等待新码流KEY0和实际取景检查，不能据此宣布高清画面验收。完整源码及报告归档，旧00f3/be1预览和85c DDR版本保留，分别有原恢复入口及`恢复相机预览_重连修正版.cmd`。这版为全像素预览，未接DDR或透视校正。详见[高清预览联调](高清预览联调_20261010.md)与`results/hardware_20261009/camera_native_state_20261010.json`。原A/B/C、Esc未改。

'''
for name in ['docs/继续工作.md', 'README.md', 'docs/实时预览联调_20261010.md']:
    p = R / name
    previous = p.read_text(encoding='utf-8-sig')
    if '## 22:44 高清预览接续' not in previous:
        first, separator, rest = previous.partition('\n')
        p.write_text(first + separator + '\n' + prefix + rest.lstrip('\n'), encoding='utf-8')
print('Saved native Program/Verify, full-resolution architecture and pending real-camera acceptance.')
