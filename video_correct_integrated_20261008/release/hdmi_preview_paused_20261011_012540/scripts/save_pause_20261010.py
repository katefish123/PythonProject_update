"""Archive the current HDMI bring-up evidence without touching original projects."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import shutil
import zipfile

R=Path(__file__).resolve().parents[1]
assert R.name=='video_correct_integrated_20261008'
O=R/'release/hdmi_bringup_paused_20261010'
O.mkdir(parents=True,exist_ok=True)
current_hash='0d15e388b4fef5bc21bb8d072d136f6f343b2d7e08b71a13275100ca9e457a20'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
current=R/'diagnostics/hdmi_runtime/results/generate_bitstream/hdmi_runtime_probe_top.sbit'
assert sha(current)==current_hash
trial=R/'diagnostics/camera_passthrough_rx_first/results/generate_bitstream/hdmi_camera_passthrough_rx_first_top.sbit'
trial_hash=sha(trial)
probe=json.loads((R/'results/hardware_20261009/hdmi_runtime_probe_20261010.json').read_text(encoding='utf-8'))
state_path=R/'docs/hardware_20261009.json'
state=json.loads(state_path.read_text(encoding='utf-8-sig'))
state.update(paused_by_user=True,last_update_utc=datetime.now(timezone.utc).isoformat(),
 current_temporary_image=str(current.relative_to(R)).replace('\\','/'),
 current_temporary_image_sha256=current_hash,
 physical_route_current='Camera -> FPGA HDMI-IN -> FPGA HDMI-OUT -> VC-002Pro -> USB PC, user confirmed',
 capture_result='OBS diagnostic pattern and hardware status; actual camera passthrough remains unverified/black',
 rx_clock_seen=probe['rx_clock_seen'],latest_diagnostic_rx_done=probe['rx_done'],
 hdmi_ack_error=probe['ack_error'],latest_diagnostic_nack_count=probe['nack_count'],
 camera_rx_measured_width=probe['rx_width'],camera_rx_measured_active_height=probe['active_height'],
 camera_rx_diagnostic_evidence='results/hardware_20261009/hdmi_runtime_probe_20261010.json',
 rx_first_trial_built=True,rx_first_trial_programmed=False,rx_first_trial_simulations_passed=False,
 rx_first_trial_sha256=trial_hash,
 pending='Paused by user. Repair RX-first simulation VTC input and local modelsim.ini; verify, then test passthrough. Real camera DDR correction and sustained acceptance remain pending.')
state_path.write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

for directory,bit in [('current_runtime_status',current),('rx_first_trial_not_programmed',trial)]:
    target=O/directory
    target.mkdir(exist_ok=True)
    for source in [bit,bit.with_suffix('.smsk')]:
        shutil.copy2(source,target/source.name)

files=[R/'README.md',state_path,R/'docs/继续工作.md',R/'docs/暂停记录_20261010.md',
 R/'docs/OBS与相机直通_20261009.md',Path(__file__),
 R/'pds/program_hdmi_runtime_probe.tcl',R/'pds/program_camera_passthrough_rx_first.tcl',
 R/'pds/program_camera_passthrough.tcl',R/'pds/program_ddr_startup_fixed.tcl',
 R/'results/hardware_20261009/camera_direct_obs_user_20261010.png',
 R/'results/hardware_20261009/hdmi_runtime_probe_20261010.png',
 R/'results/hardware_20261009/hdmi_runtime_probe_20261010.json',
 R/'results/hardware_20261009/program_camera_passthrough_20261010.log',
 R/'results/hardware_20261009/program_hdmi_runtime_probe_20261010.log']
for name in ['hdmi_runtime','camera_passthrough_rx_first']:
    folder=R/'diagnostics'/name
    files += [p for p in folder.iterdir() if p.is_file()]
    results=folder/'results'
    files += [p for p in results.iterdir() if p.is_file() and p.suffix in {'.v','.sv','.tcl','.fdc','.do','.json','.log','.ini'}]
    files += list((results/'place_route').glob('*timing_summary_after_hold_fix.txt'))
files += [R/f'rtl/hdmi/{name}.v' for name in ['hdmi_config','iic_dri','ms7200_ctl','ms7210_ctl']]
files += [R/'rtl/common/reset_sync.v',R/'constr/board_bram.fdc',
 R/'vendor/c_current/01_design_code/hdmi_vs_recover.v',R/'vendor/c_current/01_design_code/video_timing_vtc.v',
 R/'sim/tb_hdmi_config.sv']
files += [R/f'vendor/c_current/01_design_code/ip/{name}/{name}.v' for name in ['video_pll_27m_148m5','config_pll_27m_10m']]
files=sorted(set(files),key=lambda p:str(p))
assert all(p.is_file() and p.resolve().is_relative_to(R.resolve()) for p in files)
archive=O/'source_logs_evidence.zip'
with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for p in files:z.write(p,str(p.relative_to(R)).replace('\\','/'))
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert len(z.namelist())==len(files)
manifest={'saved_at_utc':datetime.now(timezone.utc).isoformat(),'paused_by_user':True,
 'current_board_image':'current_runtime_status/hdmi_runtime_probe_top.sbit',
 'current_board_program_verify_passed':True,'camera_direct_obs_verified':True,
 'camera_rx_status':probe,'camera_passthrough_verified':False,'camera_correction_verified':False,
 'rx_first_trial_built':True,'rx_first_trial_programmed':False,'rx_first_trial_simulations_passed':False,
 'main_ddr_release':'../ddr_startup_fixed_20261009',
 'main_ddr_sha256':'85c11bebe47b97621619daf1fbf0f04e33fa270f5444e481c8280ee2d5ac2875',
 'source_files_sha256':{str(p.relative_to(R)).replace('\\','/'):sha(p) for p in files},
 'archive_file_count':len(files),'archive_crc_passed':True,
 'archive_sha256':sha(archive),
 'saved_artifacts_sha256':{str(p.relative_to(O)).replace('\\','/'):sha(p)
  for p in O.rglob('*') if p.is_file() and p.suffix in {'.sbit','.smsk'}}}
(O/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
shutil.copy2(R/'docs/暂停记录_20261010.md',O/'暂停记录.md')
print(json.dumps({'archive':str(O),'source_files':len(files),'zip_crc_passed':True,
 'current_board_sha256':current_hash,'trial_sha256':trial_hash},ensure_ascii=False,indent=2))
