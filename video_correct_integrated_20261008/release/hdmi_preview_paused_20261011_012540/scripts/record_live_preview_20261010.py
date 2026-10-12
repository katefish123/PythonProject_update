"""Record this session's observations without changing historical acceptance."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import shutil

R = Path(__file__).resolve().parents[1]
H = R/'results/hardware_20261009'
log = H/'program_camera_live_retry_20261010.log'
content = log.read_text(encoding='utf-8-sig',errors='replace')
if ('COMMAND[Program] execute successfully' not in content or
    'COMMAND[Verify] execute successfully' not in content or
    any(s in content for s in ['execute fail','exec failed','Fail to compare'])):
    raise RuntimeError('The latest passthrough download has not passed')
image = 'diagnostics/camera_passthrough_rx_first/results/generate_bitstream/hdmi_camera_passthrough_rx_first_top.sbit'
digest = hashlib.sha256((R/image).read_bytes()).hexdigest()
assert digest=='cf1ddcbdb7a8dbd1c81671d111c711e2527fa03a2b9c8524c476744327b68299'
release = R/'release/camera_live_bram_20261010'
qualification = json.loads((release/'build_qualification.json').read_text(encoding='utf-8'))
for name, expected in qualification['files'].items():
    assert hashlib.sha256((release/name).read_bytes()).hexdigest()==expected, name
utc = datetime.now(timezone.utc).isoformat()
record = {'utc':utc,'priority':'Camera live view through FPGA before correction',
          'last_verified_programmed_image':image,'last_verified_programmed_sha256':digest,
          'program_verify_passed':True,'program_log':str(log.relative_to(R)),
          'capture_device_present':False,
          'capture_evidence':'OBS 19:15:35 GetDevice failed; two read-only ProcAmp enumerations found=false; all DirectShow video devices list only ASUS FHD webcam',
          'key0_after_latest_program_confirmation_pending':True,
          'raw_bram_preview_release':'release/camera_live_bram_20261010',
          'raw_bram_preview_simulations_passed':True,'raw_bram_preview_timing_passed':True,
          'raw_bram_preview_sha256':qualification['files']['camera_live_bram_top.sbit'],
          'raw_bram_preview_programmed':False,'actual_camera_display_accepted':False,
          'actual_camera_correction_accepted':False,'esc_behavior_modified':False,
          'flash_modified':False,'pending':'User reconnect capture USB and confirm KEY0; inspect native passthrough; then qualified fixed-clock BRAM preview if needed'}
(H/'live_preview_state_20261010.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
status_file = R/'docs/hardware_20261009.json'
backup = H/'hardware_status_before_live_preview_20261010.json'
if not backup.exists(): shutil.copy2(status_file,backup)
status = json.loads(status_file.read_text(encoding='utf-8-sig'))
status.update(last_update_utc=utc,current_temporary_image=image,
              current_temporary_image_sha256=digest,bitstream_sha256=digest,
              capture_device_present_this_resume=False,
              capture_result='OBS cannot reopen absent capture card; old preview frame is not current video evidence',
              pending=record['pending'],paused_by_user=False,
              actual_camera_display_accepted=False,actual_camera_correction_accepted=False,
              raw_bram_preview_release=record['raw_bram_preview_release'],
              raw_bram_preview_sha256=record['raw_bram_preview_sha256'],
              raw_bram_preview_programmed=False,
              current_boot_ddr_bist_observed=False,
              latest_camera_live_state=str((H/'live_preview_state_20261010.json').relative_to(R)))
status_file.write_text(json.dumps(status,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Saved current passthrough download, missing capture-card observation and qualified backup preview; actual camera display remains unaccepted.')
