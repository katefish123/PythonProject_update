"""Bind a newly routed DB to standalone timing and bit generation outputs."""
from pathlib import Path
import hashlib, json, re, subprocess
if not __debug__:
    raise RuntimeError('Optimized Python is prohibited: release checks must remain active')

O = Path('D:/FPGA/output/b_lens_board_trial_20261022_v5')
B = O/'seed73'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    log = (B/'project_reroute.log').read_text(errors='replace')
    assert not re.search(r'^E:|ERROR:', log, re.M)
    for phase in ['Compile', 'Synthesize', 'Device Map', 'Place & Route']:
        assert f'Process "{phase}" done.' in log, ('unfinished', phase)
    sources = json.loads((O/'source_manifest.json').read_text())['candidate_source_sha256']
    for n, h in sources.items():
        assert sha(O/'sources'/n) == h, ('source drift', n)
    db = B/'place_route/video_correct_ddr_top_pnr.adf'
    assert db.stat().st_size > 1000000
    out = B/'finish'
    out.mkdir()  # A fresh directory is mandatory; copied seed17 outputs cannot qualify.
    (out/'input_binding.json').write_text(json.dumps(dict(
        pnr_sha256=sha(db), candidate_manifest_sha256=sha(O/'source_manifest.json'),
        routed_build_log_sha256=sha(B/'project_reroute.log')), indent=2)+'\n')
    header = (O/'build.tcl').read_text().split('compile -top_module')[0]
    # A fresh shell silently skips the wrapper timing action when its project
    # has no compile/PNR state. Invoke the timing worker against the same PDS
    # explicitly after bit generation, and require its real report below.
    script = header+f'report_timing -force_to_run -input_db_file {{{db.as_posix()}}}\n'
    script += f'gen_bit_stream -force_to_run -input_db_file {{{db.as_posix()}}}\n'
    (out/'finish.tcl').write_text(script)
    with (out/'finish_console.log').open('wb') as f:
        result = subprocess.run(['D:/softwares/PDS/PDS_2022.2-SP6.4/bin/pds_shell.exe',
            '-file', str(out/'finish.tcl'), '-project_name', 'finish'], cwd=out,
            stdout=f, stderr=subprocess.STDOUT)
    assert result.returncode == 0, 'Inspect finish_console.log'
    with (out/'report_direct.log').open('wb') as f:
        timing = subprocess.run(['D:/softwares/PDS/PDS_2022.2-SP6.4/bin/pds_shell.exe',
            '-action', 'report_timing', '-project_file', str(out/'finish.pds')], cwd=out,
            stdout=f, stderr=subprocess.STDOUT)
    assert timing.returncode == 0 and 'Report timing is finished successfully.' in (out/'report_direct.log').read_text(errors='replace')
    assert (out/'video_correct_ddr_top.rtr').stat().st_size > 1000
    binding = json.loads((out/'input_binding.json').read_text())
    binding.update(timing_exit_code=timing.returncode, timing_log_sha256=sha(out/'report_direct.log'),
        timing_project_sha256=sha(out/'finish.pds'))
    (out/'input_binding.json').write_text(json.dumps(binding, indent=2)+'\n')
    assert sha(db) == json.loads((out/'input_binding.json').read_text())['pnr_sha256']
    print('FINISH_FLOW_RETURNED; run qualify.py --implementation seed73 before programming')

if __name__ == '__main__':
    main()
