"""Save the qualified software candidate without claiming hardware acceptance."""
from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,shutil,zipfile
R=Path(__file__).resolve().parents[1]
D=R/'diagnostics/camera_passthrough_rx_first'
O=R/'release/rx_first_candidate_20261010'
O.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
q=json.loads((D/'results/simulation_qualification.json').read_text(encoding='utf-8-sig'))
assert all(q[k] for k in ['normal_two_frames_passed','missing_vs_two_frames_passed','rx_first_i2c_passed'])
bit=D/'results/generate_bitstream/hdmi_camera_passthrough_rx_first_top.sbit'
assert sha(bit)=='cf1ddcbdb7a8dbd1c81671d111c711e2527fa03a2b9c8524c476744327b68299'
timing=D/'results/place_route/hdmi_camera_passthrough_rx_first_top_timing_summary_after_hold_fix.txt'
assert 'All Constraints Met.' in timing.read_text(encoding='utf-8-sig')
for p in [bit,bit.with_suffix('.smsk'),timing]:shutil.copy2(p,O/p.name)
sources=[Path(p) for p in json.loads((D/'results/sources.json').read_text(encoding='utf-8'))]
files=sources+[p for p in D.iterdir() if p.is_file()]
files += [p for p in (D/'results').iterdir() if p.is_file() and p.suffix in {'.sv','.do','.tcl','.fdc','.json','.log','.ini'}]
files += [R/'docs/恢复联调_20261010.md',R/'pds/program_camera_passthrough_rx_first.tcl',
          R/'pds/program_rx_first_1mhz_resume_20261010.tcl',Path(__file__)]
files += [p for p in (R/'results/hardware_20261009').iterdir() if p.is_file() and (
 p.name in ['program_rx_first_resume_20261010.log','verify_rx_first_1mhz_20261010.log',
 'program_rx_first_1mhz_resume_20261010.log','verify_rx_first_500khz_20261010.log',
 'program_runtime_isc_1mhz_20261010.log','stalled_isc_recovery_20261010.json',
 'readback_analysis_resume_20261010.json'])]
files=sorted(set(files),key=str)
assert all(p.is_file() and p.resolve().is_relative_to(R.resolve()) for p in files)
archive=O/'source_simulation_evidence.zip'
with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for p in files:z.write(p,p.relative_to(R).as_posix())
with zipfile.ZipFile(archive) as z:assert z.testzip() is None
manifest={'saved_at_utc':datetime.now(timezone.utc).isoformat(),'candidate_only':True,
 'hardware_verification_passed_this_resume':False,'camera_passthrough_verified_this_resume':False,
 'simulation':q,'pds_constraints_met':True,'bitstream_sha256':sha(bit),
 'mask_sha256':sha(bit.with_suffix('.smsk')),'archive_crc_passed':True,'archive_sha256':sha(archive),
 'source_files_sha256':{p.relative_to(R).as_posix():sha(p) for p in files}}
(O/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
shutil.copy2(R/'docs/恢复联调_20261010.md',O/'候选与硬件待验记录.md')
state_path=R/'docs/hardware_20261009.json'
state=json.loads(state_path.read_text(encoding='utf-8-sig'))
state.update(paused_by_user=False,resumed_by_user=True,last_update_utc=datetime.now(timezone.utc).isoformat(),
 current_temporary_image='Unverified after resumed programming attempts; do not inherit last session state',
 configuration_verify_passed=False,rx_first_trial_simulations_passed=True,
 rx_first_resume_program_reported_success=True,rx_first_resume_verify_passed=False,
 capture_device_present_this_resume=True,obs_device_path_needs_refresh=True,
 pending='Await user board power cycle/JTAG reseat and OBS device selection, then recover hardware programming verification')
state_path.write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'candidate_archive':str(O),'source_files':len(files),'zip_crc_passed':True,
 'hardware_accepted':False},ensure_ascii=False,indent=2))
