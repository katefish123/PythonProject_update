"""Preserve the failed native checks and verified diagnostic rollback."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import shutil

R = Path(__file__).resolve().parents[1]
H = R / 'results/hardware_20261009'
image = 'release/camera_live_bram_reconnect_20261010/camera_live_bram_top.sbit'
digest = hashlib.sha256((R / image).read_bytes()).hexdigest()
assert digest == 'be1a72cade3008e25cff3f6925bf6347fea8211da6e5447fdd82ef137e7f5212'
program = H / 'program_camera_live_bram_reconnect_20261011_003652.log'
text = program.read_text(encoding='utf-8-sig', errors='replace')
assert all(t in text for t in ['COMMAND[Program] execute successfully', 'COMMAND[Verify] execute successfully'])
assert not any(t in text for t in ['execute fail', 'exec failed', 'Fail to compare'])
latest_log = max((R / 'tools/obs-studio/portable/config/obs-studio/logs').glob('*.txt'), key=lambda p: p.stat().st_mtime)
obs_text = latest_log.read_text(encoding='utf-8-sig', errors='replace')
assert '00:35:54.117:' in obs_text and 'fps: 30.00 (interval: 333333)' in obs_text
scene_path = R / 'tools/obs-studio/portable/config/obs-studio/basic/scenes/FPGA.json'
scene = json.loads(scene_path.read_text(encoding='utf-8-sig'))
sources = [s for s in scene['sources'] if s['id'] == 'dshow_input']
assert len(sources) == 1
assert sources[0]['settings']['resolution'] == '1920x1080'
assert sources[0]['settings']['frame_interval'] == 333333
shutil.copy2(scene_path, H / 'obs_scene_mjpeg_1080p30_20261011.json')
shutil.copy2(latest_log, H / 'obs_after_flicker_format_check_20261011.txt')
record = {
    'utc': datetime.now(timezone.utc).isoformat(), 'current_image': image,
    'current_image_sha256': digest, 'program_verify_passed': True,
    'program_log': str(program.relative_to(R)), 'flash_modified': False,
    'native_tx_first_user_result': 'Black; flickering after restart',
    'native_rx_first_user_result': 'Black after KEY0 and R50 restart',
    'user_1080p30_result': 'No image',
    'obs_capture_format_verified': '1920x1080 MJPEG 30fps, buffering and hardware decoding disabled',
    'previous_obs_log_findings': 'Repeated EOI missing and Error decoding video before 1080p30 change',
    'flicker_root_cause_proven': False,
    'diagnostic_grid_observed_after_restore': True,
    'current_receiver_probe_decoded': False,
    'actual_camera_display_accepted': False,
    'continuous_camera_display_verified': False,
    'actual_camera_correction_accepted': False,
    'pending': 'User save OBS source screenshot; decode real native D104/B401 grid to distinguish RX input loss from native TX/capture problems',
    'retained_native_releases': ['release/camera_live_native_20261010', 'release/camera_native_rx_first_20261010'],
    'original_A_B_C_modified': False, 'esc_behavior_modified': False,
    'obs_recording_running': False, 'obs_streaming_started': False,
}
(H / 'camera_flicker_state_20261011.json').write_text(json.dumps(record, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
state_path = R / 'docs/hardware_20261009.json'
status = json.loads(state_path.read_text(encoding='utf-8-sig'))
status.update(last_update_utc=record['utc'], current_temporary_image=image,
              current_temporary_image_sha256=digest, bitstream_sha256=digest,
              latest_camera_live_state='results/hardware_20261009/camera_flicker_state_20261011.json',
              obs_actual_format=record['obs_capture_format_verified'],
              capture_result='Native TX/RX-first remain black; diagnostic BRAM rollback successfully shows real board status grid',
              pending=record['pending'], actual_camera_display_accepted=False,
              continuous_camera_display_verified=False, actual_camera_correction_accepted=False)
state_path.write_text(json.dumps(status, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
prefix = '''## 2026-10-11 黑屏闪烁检查

用户完成两种完整分辨率码流的KEY0/R50重开对照，均黑屏，发送优先还报告闪烁。OBS在60fps/MJPEG时连续出现EOI缺失和解码失败，不能把它们直接断言为FPGA时序故障。用户已将采集改为1920×1080/MJPEG/30fps，日志与保存配置确认生效，仍报告无图像。

已回退到保留的双BRAM重连诊断版be1a72...，Program/Verify通过：`program_camera_live_bram_reconnect_20261011_003652.log`。OBS确实显示板内红绿格；当前尚未解码接收状态，已请用户保存OBS“截屏(源)”，随后直接读取本机文件。两个高清发布和原工程均保留，未写Flash，Esc未改。

当前状态为`results/hardware_20261009/camera_flicker_state_20261011.json`。在得到当前原生状态图前，不继续随机换码流或重复复位；先确定RX频率、有效帧和宽高，再决定连接检查或原生发送时序检查。

'''
for name in ['docs/继续工作.md', 'README.md', 'docs/高清预览联调_20261010.md']:
    p = R / name
    before = p.read_text(encoding='utf-8-sig')
    if '## 2026-10-11 黑屏闪烁检查' not in before:
        first, sep, rest = before.partition('\n')
        p.write_text(first+sep+'\n'+prefix+rest.lstrip('\n'), encoding='utf-8')
print('Saved verified diagnostic rollback, 1080p30 capture format and unresolved flicker evidence.')
