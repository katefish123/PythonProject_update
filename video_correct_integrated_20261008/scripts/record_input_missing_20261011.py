"""Record a real decoded no-input frame and user-led physical comparison."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json

R = Path(__file__).resolve().parents[1]
H = R / 'results/hardware_20261009'
record = json.loads((H / 'camera_flicker_state_20261011.json').read_text(encoding='utf-8'))
probe_file = H / 'bram_probe_after_native_black_20261011.json'
probe = json.loads(probe_file.read_text(encoding='utf-8'))
assert probe['word_hex'].startswith('d104')
assert probe['tx_done'] and probe['rx_probe_done'] and probe['tx_probe_done']
assert not probe['config_error'] and probe['nack_count'] == 0
assert not probe['rx_done'] and not probe['rx_clock_seen'] and not probe['de_seen']
assert not probe['frame_valid'] and probe['frequency_registers'] == '0x00010000'
frame = H / 'bram_probe_after_native_black_20261011.png'
record.update(utc=datetime.now(timezone.utc).isoformat(), current_receiver_probe_decoded=True,
              receiver_probe=probe,receiver_probe_file=str(probe_file.relative_to(R)),
              receiver_probe_frame=str(frame.relative_to(R)),
              receiver_probe_frame_sha256=hashlib.sha256(frame.read_bytes()).hexdigest(),
              source_screenshot_saved=True,
              receiver_input_missing_at_capture=True,
              receiver_input_missing_reason='No RX pixel clock observed since reset, no DE/VS/HS, no frame; frequency data 00010000, width and height zero; I2C probes pass with no NACK',
              computer_use_paused_by_user=True,
              pending='User-operated R50 direct-to-capture comparison with unchanged OBS MJPEG 1080p30; no desktop automation until user resumes it')
(H / 'camera_flicker_state_20261011.json').write_text(json.dumps(record, ensure_ascii=False, indent=2)+'\n',encoding='utf-8')
state_path = R / 'docs/hardware_20261009.json'
status = json.loads(state_path.read_text(encoding='utf-8-sig'))
status.update(last_update_utc=record['utc'], current_receiver_probe_decoded=True,
              receiver_input_missing_at_capture=True, computer_use_paused_by_user=True,
              capture_result='Decoded real D104/B401 grid: TX ready, RX scratch probe passes, NACK=0; no receiver pixel clock/DE/frame',
              pending=record['pending'])
state_path.write_text(json.dumps(status,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
prefix = '''## 2026-10-11 已读取真实接收状态

OBS“截屏(源)”实际已保存到Videos，用户无需发送文件。已复制`Screenshot 2026-10-11 00-41-37.png`到`results/hardware_20261009/bram_probe_after_native_black_20261011.png`并通过D104/B401双签名解码。TX完成、RX/TX探测均通过、NACK=0，但RX未完成、复位后没有观察到接收像素时钟/DE/HS/VS、宽高0、完整帧false，频率寄存器00010000。当前板上仍为be1双BRAM重连诊断，下载回读已通过。

该结果把当前故障定位到相机输入/HDMI接收链路，仍不能单凭它区分相机、线缆、EDID协商或RX配置。已请用户将相机直接接采集卡，OBS保持1080p30/MJPEG，对比当前实时画面。用户明确“暂时不用computeruse”：停止桌面控制，工程CLI/文件分析继续，整项任务未暂停。下一步等直连结果，再决定上游连接/协商检查；两个高清版、原预览、DDR版本和Esc均保留。

'''
for name in ['docs/继续工作.md','README.md','docs/高清预览联调_20261010.md']:
    p=R/name
    before=p.read_text(encoding='utf-8-sig')
    if '## 2026-10-11 已读取真实接收状态' not in before:
        first,sep,rest=before.partition('\n')
        p.write_text(first+sep+'\n'+prefix+rest.lstrip('\n'),encoding='utf-8')
print('Saved real no-input RX evidence; computer-use paused as requested, engineering continues.')
