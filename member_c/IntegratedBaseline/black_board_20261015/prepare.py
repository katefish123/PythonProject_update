"""Prepare the independent filtered-clock candidate; never inherit acceptance."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CAND = Path('diagnostics/ddr_camera_hires_prefetch_20261012/results')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    out = parser.parse_args().output.resolve()
    if out.exists():
        raise SystemExit('Use a fresh output directory; bound runs must be preserved')
    subprocess.run([sys.executable, str(HERE.parent/'inline_geometry_20261014/prepare.py'),
                    '--output', str(out)], check=True)
    shutil.copyfile(HERE/'capture_geometry.v', out/'rtl/algo/capture_geometry.v')
    core = out/'rtl/top/video_correct_ddr_core.v'
    code = core.read_text()
    needle = '.rx_clk(rx_clk),.rx_rst_n(rx_rst_n),.sample_valid(sample_v)'
    assert code.count(needle) == 1, 'Geometry clock interface changed'
    # Public reset only: processor_rst is also asserted by each session CLEAR.
    code = code.replace(needle, '.rx_clk(rx_clk),.rx_rst_n(rx_rst_n),'
                        '.proc_clk(proc_clk),.proc_rst_n(proc_rst_n),.sample_valid(sample_v)')
    core.write_text(code)
    cases_file = out/CAND/'simulation_cases.json'
    cases = json.loads(cases_file.read_text())
    for name, marker in [('tb_capture_geometry', 'CAPTURE_GEOMETRY_PASS'),
                         ('tb_dense_geometry', 'DENSE_GEOMETRY_PASS')]:
        shutil.copyfile(HERE/(name+'.sv'), out/'fullhd_tests'/(name+'.sv'))
        script = (out/CAND/'tb_capture_geometry.do').read_text()
        if name != 'tb_capture_geometry':
            script = script.replace('tb_capture_geometry', name)
        (out/CAND/(name+'.do')).write_text(script)
        cases[name] = marker
    cases_file.write_text(json.dumps(cases, indent=2)+'\n')
    manifest_file = out/'reproduction_manifest.json'
    manifest = json.loads(manifest_file.read_text())
    manifest['optimization'] = 'filtered_black_geometry_clock_candidate'
    manifest['board_replacement_allowed'] = False
    manifest['known_unmerged'] = ['540dd628 capture bursts, preview, diagnostics and recovery']
    for name in manifest['files']:
        manifest['files'][name]['local_sha256'] = hashlib.sha256((out/name).read_bytes()).hexdigest()
    for src in [out/'fullhd_tests/tb_dense_geometry.sv', out/CAND/'tb_dense_geometry.do']:
        manifest['files'][src.relative_to(out).as_posix()] = {
            'local_sha256': hashlib.sha256(src.read_bytes()).hexdigest()}
    manifest_file.write_text(json.dumps(manifest, indent=2)+'\n')
    print('FILTERED_CLOCK_CANDIDATE_READY tests='+str(len(cases)))


if __name__ == '__main__':
    main()
