"""Record the newest RX-first native image, keeping earlier observations."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json

R = Path(__file__).resolve().parents[1]
H = R / 'results/hardware_20261009'
image = 'release/camera_native_rx_first_20261010/camera_native_rx_first_top.sbit'
digest = hashlib.sha256((R / image).read_bytes()).hexdigest()
assert digest == 'b918087a2ec5179e78f1a3f78e903538e401abbc120ba40201abb45a9fb5cbc2'
program = H / 'program_camera_native_rx_first_20261010_225301.log'
text = program.read_text(encoding='utf-8-sig', errors='replace')
assert all(t in text for t in ['COMMAND[Program] execute successfully', 'COMMAND[Verify] execute successfully'])
assert not any(t in text for t in ['execute fail', 'exec failed', 'Fail to compare'])
release = R / 'release/camera_native_rx_first_20261010'
qualification = json.loads((release / 'build_qualification.json').read_text())
for name, expected in qualification['files'].items():
    assert hashlib.sha256((release / name).read_bytes()).hexdigest() == expected, name
previous = json.loads((H / 'camera_native_state_20261010.json').read_text(encoding='utf-8'))
record = dict(previous)
proof = next(H.glob('native_rx_first_before_reset_20261010.*'))
record.update(utc=datetime.now(timezone.utc).isoformat(), current_image=image,
              current_image_sha256=digest, program_log=str(program.relative_to(R)),
              config_order='RX first, then TX, then return bus ownership to RX and replay its deferred request',
              integrated_rx_first_polling_failure_reproduced=True,
              receiver_polling_repair_seven_checks_passed=True,
              previous_tx_first_native_key0_user_result='No image',
              previous_tx_first_native_sha256=previous['current_image_sha256'],
              latest_observation='OBS black before latest physical KEY0 and camera restart confirmation',
              latest_window_evidence=str(proof.relative_to(R)),
              pending='Await user KEY0 and R50 restart after RX-first b918 image; observe actual frame, refresh capture source if required, save native image and continuity evidence',
              restore_entries=previous['restore_entries']+['下载高清相机预览_接收优先.cmd'])
record['retained_releases'] = previous['retained_releases']+['release/camera_live_native_20261010']
(H / 'camera_rx_first_native_state_20261010.json').write_text(json.dumps(record, ensure_ascii=False, indent=2)+'\n',encoding='utf-8')
state_file = R / 'docs/hardware_20261009.json'
status = json.loads(state_file.read_text(encoding='utf-8-sig'))
status.update(last_update_utc=record['utc'], current_temporary_image=image,
              current_temporary_image_sha256=digest, bitstream_sha256=digest,
              latest_camera_live_state='results/hardware_20261009/camera_rx_first_native_state_20261010.json',
              native_rx_first_preview_programmed=True, native_rx_first_preview_verify_passed=True,
              native_rx_first_preview_sha256=digest,
              capture_result=record['latest_observation'],pending=record['pending'])
state_file.write_text(json.dumps(status,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
prefix = '''## 22:55 当前高清接收优先版本

发送优先完整分辨率00e696...下载后用户KEY0仍无画面。另发现本工程接收优先配置在TX完成后未交回RX，独立真实总线仿真已复现轮询停止；新副本增加空闲时交回RX和暂存被推迟的RX请求，接收/发送两顺序、HDMI/DVI两次重连、原NACK/开漏检查及两整帧像素检查共7项全部通过。原C材料未改，不能断言这一故障解释了所有实体黑屏。

当前板上已Program/Verify通过的码流改为`release/camera_native_rx_first_20261010/camera_native_rx_first_top.sbit`，SHA256 `b918087a2ec5179e78f1a3f78e903538e401abbc120ba40201abb45a9fb5cbc2`；日志`program_camera_native_rx_first_20261010_225301.log`。PDS所有约束满足，slow RX setup1.557ns、RX→TX1.968ns。最新实际OBS观察仍为黑屏，等待本码流KEY0和R50重新开机后的确认，尚未高清或校正验收。恢复/下载入口均保留，包括新增`下载高清相机预览_接收优先.cmd`。

当前状态JSON为`results/hardware_20261009/camera_rx_first_native_state_20261010.json`；不要重跑硬编码早期码流的记录脚本覆盖它。Esc、原材料及旧发布完整保留。

'''
for name in ['docs/继续工作.md','README.md','docs/高清预览联调_20261010.md']:
    p=R/name
    before=p.read_text(encoding='utf-8-sig')
    if '## 22:55 当前高清接收优先版本' not in before:
        first,sep,rest=before.partition('\n')
        p.write_text(first+sep+'\n'+prefix+rest.lstrip('\n'),encoding='utf-8')
print('Saved verified b918 RX-first native download and pending physical display acceptance.')
