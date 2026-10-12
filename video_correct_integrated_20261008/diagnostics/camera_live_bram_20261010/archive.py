"""Archive only a fully simulated, timed preview build; do not claim hardware acceptance."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import shutil
import zipfile

D = Path(__file__).resolve().parent
R = D.parents[1]
O = D/'results'
release = R/'release/camera_live_bram_20261010'
report = O/'place_route/camera_live_bram_top_timing_summary_after_hold_fix.txt'
if 'All Constraints Met' not in report.read_text(encoding='utf-8-sig'):
    raise RuntimeError('Do not release or program a preview with failed timing')
sim = json.loads((O/'simulation_qualification.json').read_text(encoding='utf-8-sig'))
if len(sim['tests'])!=3 or any(t['exit_code']!=0 for t in sim['tests'].values()):
    raise RuntimeError('Preview tests not qualified')
source_hashes = json.loads((O/'source_hashes.json').read_text(encoding='utf-8'))
for name, expected in source_hashes.items():
    if hashlib.sha256(Path(name).read_bytes()).hexdigest()!=expected:
        raise RuntimeError('Build source changed since preparation: '+name)
release.mkdir(exist_ok=False)
files = [O/'generate_bitstream/camera_live_bram_top.sbit',
         O/'generate_bitstream/camera_live_bram_top.smsk', report,
         O/'source_hashes.json',O/'simulation_qualification.json',O/'build_registered_output.log']
for p in files: shutil.copy2(p,release/p.name)
extra = [D/'prepare.py',D/'archive.py',D/'decode_status.py',D/'tb_camera_live_bram.v',D/'run_checks.ps1',
         R/'pds/program_camera_live_bram.tcl',R/'scripts/program_camera_live_bram.ps1']
with zipfile.ZipFile(release/'source_snapshot.zip','w',zipfile.ZIP_DEFLATED) as z:
    for p in sorted({Path(n) for n in source_hashes}|set(extra)):
        z.write(p,p.relative_to(R).as_posix())
with zipfile.ZipFile(release/'source_snapshot.zip') as z:
    if z.testzip() is not None: raise RuntimeError('Archive CRC failed')
checksums = {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in release.iterdir() if p.is_file()}
qualification = {'utc':datetime.now(timezone.utc).isoformat(),'simulations_passed':True,
                 'timing_passed':True,'actual_camera_display_accepted':False,
                 'capture_size':[320,180],'output_size':[1920,1080],
                 'output_hz':60,'flash_modified':False,'files':checksums}
(release/'build_qualification.json').write_text(json.dumps(qualification,indent=2)+'\n',encoding='utf-8')
print(json.dumps(qualification,indent=2))
