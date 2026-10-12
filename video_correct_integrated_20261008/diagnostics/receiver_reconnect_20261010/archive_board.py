"""Archive the recovery candidate without claiming that it is programmed."""
from pathlib import Path
from datetime import datetime,timezone
import hashlib
import json
import shutil
import zipfile

D=Path(__file__).resolve().parent
R=D.parents[1]
O=D/'board_results'
release=R/'release/camera_live_bram_reconnect_20261010'
timing=O/'place_route/camera_live_bram_top_timing_summary_after_hold_fix.txt'
assert 'All Constraints Met' in timing.read_text(encoding='utf-8-sig')
tests=json.loads((D/'results/simulation_qualification.json').read_text(encoding='utf-8-sig'))
assert tests['baseline_failure_reproduced'] and all(t['passed'] for t in tests['tests'].values())
source_hashes=json.loads((O/'source_hashes.json').read_text(encoding='utf-8'))
for p,digest in source_hashes.items():assert hashlib.sha256(Path(p).read_bytes()).hexdigest()==digest,p
release.mkdir(exist_ok=False)
files=[O/'generate_bitstream/camera_live_bram_top.sbit',O/'generate_bitstream/camera_live_bram_top.smsk',
       timing,O/'source_hashes.json',O/'build_run.log',D/'results/simulation_qualification.json',
       D/'results/baseline.run.log',D/'results/fixed_hdmi.run.log',D/'results/fixed_dvi.run.log']
for p in files:shutil.copy2(p,release/p.name)
extras=[D/'prepare.py',D/'prepare_board.py',D/'archive_board.py',D/'run_checks.ps1',D/'tb_rx_reconnect.sv',
        R/'pds/program_camera_live_bram_reconnect.tcl',R/'scripts/program_camera_live_bram_reconnect.ps1']
with zipfile.ZipFile(release/'source_snapshot.zip','w',zipfile.ZIP_DEFLATED) as z:
    for p in sorted({Path(n) for n in source_hashes}|set(extras)):
        z.write(p,p.relative_to(R).as_posix())
with zipfile.ZipFile(release/'source_snapshot.zip') as z:assert z.testzip() is None
record={'utc':datetime.now(timezone.utc).isoformat(),'simulations_passed':True,'timing_passed':True,
        'unchanged_video_pipeline_qualification':'release/camera_live_bram_20261010/simulation_qualification.json',
        'receiver_reconnect_tests':tests,'hardware_programmed':False,'actual_camera_display_accepted':False,
        'capture_size':[320,180],'output_size':[1920,1080],'output_hz':60,'flash_modified':False,
        'files':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in release.iterdir() if p.is_file()}}
(release/'build_qualification.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
print(json.dumps(record,indent=2))
