"""Archive only a fully simulated and timed native camera candidate."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import shutil
import zipfile

D = Path(__file__).resolve().parent
R = D.parents[1]
O = D / 'results'
L = R / 'release/camera_live_native_20261010'
timing = O / 'place_route/camera_live_native_top_timing_summary_after_hold_fix.txt'
assert 'All Constraints Met' in timing.read_text(encoding='utf-8-sig')
tests = json.loads((O / 'simulation_qualification.json').read_text(encoding='utf-8-sig'))
assert len(tests['tests']) == 4 and all(t['passed'] for t in tests['tests'].values())
hashes = json.loads((O / 'source_hashes.json').read_text(encoding='utf-8'))
for name, digest in hashes.items():
    assert hashlib.sha256(Path(name).read_bytes()).hexdigest() == digest, name
build = (O / 'build_run.log').read_text(encoding='utf-8-sig', errors='replace')
assert 'Executing : gen_bit_stream successfully.' in build

# Clone the proven CRAM-only, hash-gated programming entry under a new name.
tcl = (R / 'pds/program_camera_live_bram_reconnect.tcl').read_text(encoding='utf-8')
tcl = tcl.replace('camera_live_bram_reconnect_20261010', 'camera_live_native_20261010')
tcl = tcl.replace('camera_live_bram_top', 'camera_live_native_top')
tcl_path = R / 'pds/program_camera_live_native.tcl'
tcl_path.write_text(tcl, encoding='utf-8')
driver = (R / 'scripts/program_camera_live_bram_reconnect.ps1').read_text(encoding='utf-8')
driver = driver.replace('camera_live_bram_reconnect_20261010', 'camera_live_native_20261010')
driver = driver.replace('camera_live_bram_reconnect', 'camera_live_native')
driver = driver.replace('camera_live_bram_top', 'camera_live_native_top')
driver = driver.replace('Raw-camera preview', 'Full-resolution camera preview')
driver_path = R / 'scripts/program_camera_live_native.ps1'
driver_path.write_text(driver, encoding='utf-8')
entry = (R / '恢复相机预览.cmd').read_text(encoding='utf-8')
entry = entry.replace('program_camera_live_bram.ps1', 'program_camera_live_native.ps1')
(R / '下载高清相机预览.cmd').write_text(entry, encoding='ascii')

L.mkdir(exist_ok=False)
files = [O / 'generate_bitstream/camera_live_native_top.sbit',
         O / 'generate_bitstream/camera_live_native_top.smsk', timing,
         O / 'source_hashes.json', O / 'provenance.json', O / 'build_run.log',
         O / 'simulation_qualification.json']
files += [O / f'{name}.run.log' for name in tests['tests']]
for p in files:
    shutil.copy2(p, L / p.name)
extras = list(D.glob('*.py')) + list(D.glob('*.ps1')) + [tcl_path, driver_path]
extras += list(O.glob('*.do')) + list(O.glob('*.sv')) + [O / 'video_timing_vtc.v']
with zipfile.ZipFile(L / 'source_snapshot.zip', 'w', zipfile.ZIP_DEFLATED) as z:
    for p in sorted({Path(n) for n in hashes} | set(extras)):
        z.write(p, p.relative_to(R).as_posix())
with zipfile.ZipFile(L / 'source_snapshot.zip') as z:
    assert z.testzip() is None
record = {
    'utc': datetime.now(timezone.utc).isoformat(),
    'simulations_passed': True, 'timing_passed': True,
    'tests': tests, 'native_rgb888_every_pixel': True,
    'downsample_or_upscale': False, 'frame_buffer_or_ddr': False,
    'input_format_target': '1920x1080 progressive at 59.94/60 Hz',
    'output_clock': 'Actual receiver pixel clock forwarded to transmitter',
    'config_order': 'TX first; preserve receiver polling after initialization',
    'hardware_programmed': False, 'actual_camera_display_accepted': False,
    'flash_modified': False,
    'files': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in L.iterdir() if p.is_file()},
}
(L / 'build_qualification.json').write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
print(json.dumps({k: record[k] for k in ['simulations_passed', 'timing_passed', 'files']}, indent=2))
