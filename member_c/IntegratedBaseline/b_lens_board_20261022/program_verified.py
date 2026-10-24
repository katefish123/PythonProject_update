"""Program only the qualified CRAM image; record success only after readback."""
from pathlib import Path
import argparse, datetime, hashlib, json, re, subprocess
if not __debug__:
    raise RuntimeError('Optimized Python is prohibited: release checks must remain active')

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--release', type=Path, required=True)
    out = parser.parse_args().release.resolve()
    q = json.loads((out/'qualification.json').read_text())
    assert q['ready_for_authorized_cram_experiment'] and q['timing_qualified']
    bit, mask = Path(q['bitstream']), Path(q['mask'])
    assert bit.parent == out and mask.parent == out
    assert sha(bit) == q['bitstream_sha256'] and sha(mask) == q['mask_sha256']
    assert sha(Path(q['final_timing_report'])) == q['final_timing_sha256']
    sources = out.parent/'sources'
    for n,h in q['candidate_source_sha256'].items():
        assert sha(sources/n) == h, ('source changed after qualification', n)
    expected = ('cfg_set_tcl_break -flag true\ncfg_connect -ip 127.0.0.1 -port 65420\ncfg_scan_chain\n'
        + f'cfg_assign_file -file {{{bit.as_posix()}}} -device_index 0\n'
        + 'cfg_set_device_property -device_index 0 -program 1\ncfg_program -device_index 0\n'
        + 'cfg_verify -device_index 0\ncfg_disconnect\ncfg_close\n')
    assert (out/'program.tcl').read_text() == expected, 'Unexpected programming commands'
    assert not (out/'program.log').exists(), 'Preserve previous attempt; inspect before retrying'
    with (out/'program.log').open('wb') as f:
        result = subprocess.run([
            'D:/softwares/PDS/PDS_2022.2-SP6.4/bin/cdt_cfg_shell.exe',
            '-file', str(out/'program.tcl')], cwd=out, stdout=f, stderr=subprocess.STDOUT)
    raw = (out/'program.log').read_bytes()
    log = raw.decode('utf-16' if raw.startswith((b'\xff\xfe', b'\xfe\xff')) else 'utf-8-sig', errors='replace')
    assert result.returncode == 0 and not re.search(r'^E:|ERROR:', log, re.M), 'Programming failed; inspect program.log'
    for proof in ['PG2L100H', 'COMMAND[Program] execute successfully',
                  'Executing : cfg_program -device_index 0 successfully.',
                  'COMMAND[Verify] execute successfully',
                  'Executing : cfg_verify -device_index 0 successfully.']:
        assert proof in log, ('Missing hardware proof', proof)
    record = dict(hardware_programmed=True, readback_verified=True, target='PG2L100H',
        mode='temporary CRAM', flash_programmed=False,
        timestamp=datetime.datetime.now(datetime.timezone.utc).isoformat(),
        bitstream_sha256=sha(bit), mask_sha256=sha(mask), program_log_sha256=sha(out/'program.log'),
        qualification_sha256=sha(out/'qualification.json'),
        optical_acceptance=False, real_video_acceptance=False)
    (out/'hardware_programming.json').write_text(json.dumps(record, indent=2)+'\n')
    print('CRAM_PROGRAM_AND_READBACK_VERIFIED', sha(bit))

if __name__ == '__main__':
    main()
