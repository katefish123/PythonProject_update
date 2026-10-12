"""Save verified raw-preview programming and real capture observations."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json

R = Path(__file__).resolve().parents[1]
H = R/'results/hardware_20261009'
log = H/'program_camera_live_bram_20261010_195231.log'
text = log.read_text(encoding='utf-8-sig',errors='replace')
assert 'COMMAND[Program] execute successfully' in text
assert 'COMMAND[Verify] execute successfully' in text
assert not any(t in text for t in ['execute fail','exec failed','Fail to compare'])
image = 'release/camera_live_bram_20261010/camera_live_bram_top.sbit'
digest = hashlib.sha256((R/image).read_bytes()).hexdigest()
assert digest=='00f3a1aec7c75893ba2ecccb09578379512f8f8d92b6a2d765bc53cea3cc1816'
probe = json.loads((H/'camera_bram_initial_grid_20261010.json').read_text(encoding='utf-8'))
assert probe['word_hex'].startswith('d104')
assert probe['tx_done'] and not probe['config_error'] and probe['nack_count']==0
device = json.loads((H/'dshow_current_device_resume_20261010.json').read_text(encoding='utf-8-sig'))
assert device['found'] and device['read_only']
utc = datetime.now(timezone.utc).isoformat()
record = {
    'utc':utc,'current_image':image,'current_image_sha256':digest,
    'program_verify_passed':True,'program_log':str(log.relative_to(R)),
    'capture_device_present':True,'capture_device_path':device['devices'][0]['device_path'],
    'obs_actual_format':'1920x1080 MJPEG 60fps; custom mode, source screenshot',
    'rx_first_after_key0_result':'After fresh capture identifier update, source displayed no input signal',
    'rx_first_evidence':'results/hardware_20261009/native_rx_first_after_key0_no_signal_20261010.jpg',
    'fixed_clock_output_visible':True,'raw_preview_probe':probe,
    'actual_camera_display_accepted':False,'actual_camera_correction_accepted':False,
    'pending':'User restart R50 in movie live view; confirm KEY0 after new BRAM preview download; then reobserve status and real pixels',
    'esc_behavior_modified':False,'flash_modified':False,
    'camera_manual':'https://cam.start.canon/zh/C011/manual/html/UG-05_Shooting-2_0160.html',
}
(H/'camera_bram_live_state_20261010.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
status_file = R/'docs/hardware_20261009.json'
status = json.loads(status_file.read_text(encoding='utf-8-sig'))
status.update(last_update_utc=utc,current_temporary_image=image,
              current_temporary_image_sha256=digest,bitstream_sha256=digest,
              capture_device_present_this_resume=True,obs_device_path_needs_refresh=False,
              obs_actual_format=record['obs_actual_format'],raw_bram_preview_programmed=True,
              raw_bram_preview_configuration_verify_passed=True,
              capture_result='Real fixed-clock diagnostic grid received; RX not ready, no source pixel clock, frame invalid and zero captured samples',
              actual_camera_display_accepted=False,actual_camera_correction_accepted=False,
              current_boot_ddr_bist_observed=False,pending=record['pending'],paused_by_user=False,
              latest_camera_live_state='results/hardware_20261009/camera_bram_live_state_20261010.json')
status_file.write_text(json.dumps(status,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Saved verified BRAM preview and real no-input probe; camera video acceptance remains pending.')
