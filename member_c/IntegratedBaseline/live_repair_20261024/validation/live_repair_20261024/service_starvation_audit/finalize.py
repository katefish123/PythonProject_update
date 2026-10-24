"""Offline verification and evidence binding; starts no simulator."""
from pathlib import Path
import hashlib, json, re

ROOT = Path(__file__).resolve().parent
PACKAGE = Path('D:/FPGA/deliveries/FullHD_Lens_IntegratedRepair_20261023')
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
q = json.loads((PACKAGE/'release/qualification.json').read_text())
binding = json.loads((ROOT/'bench_binding.json').read_text())
assert sha(Path(binding['parent_bench'])) == binding['parent_bench_sha256']
assert sha(ROOT/'prepare_service_bench.py') == binding['generator_sha256']
assert sha(ROOT/'tb_service_starvation.sv') == binding['generated_bench_sha256']
runs = {}
for label, adverse in [('control_2', False), ('adverse', True)]:
    out = ROOT/label
    r = json.loads((out/'result.json').read_text())
    e = json.loads((out/'execution.json').read_text())
    assert all(r[k] == v for k, v in e.items())
    assert r['package_bit_sha256'] == q['bitstream_sha256']
    assert r['qualification_sha256'] == sha(PACKAGE/'release/qualification.json')
    assert r['runner_sha256'] == sha(ROOT/'run_service.py')
    assert r['bench_binding_sha256'] == sha(ROOT/'bench_binding.json')
    assert len(r['production_sha256']) == 45
    for name, h in r['production_sha256'].items():
        assert sha(out/name) == sha(PACKAGE/'sources'/name) == q['candidate_source_sha256'][name] == h
    assert sha(out/'tb_service_starvation.sv') == r['bench_sha256'] == binding['generated_bench_sha256']
    assert r['commands'][1]['args'] == ['vlog.exe', '-sv', *r['production_sha256'], 'tb_service_starvation.sv']
    assert r['commands'][2]['args'] == ['vsim.exe', '-c', '-voptargs=+acc', '-gADVERSE='+str(int(adverse)), 'tb_service_starvation', '-do', 'run -all;quit -f']
    for i, c in enumerate(r['commands']):
        assert c['exit_code'] == 0 and sha(out/f'step{i}.log') == c['log_sha256']
        text = (out/f'step{i}.log').read_text()
        assert '** Warning:' not in text and '** Error:' not in text
        if i < 2:
            assert '** Fatal:' not in text
    log = (out/'step2.log').read_text()
    if adverse:
        assert log.count('** Fatal:') == 1 and 'Errors: 1, Warnings: 0' in log
        assert '** Fatal: SERVICE_STARVATION_REPRO' in log
        assert 'rejected=3 good=1 raw=1 pix_id=1 actual_raw=1' in log
        assert 'r12=0 r13=3 r14=0 r15=0 rx_close12=0 rx_close13=3 fifo_peak=1024 fifo_full_cycles=844' in log
        assert 'pixel_errors=834825 underrun=1 engine_fault=0 source_fault=0000' in log
        assert r['target_reproduced'] and not r['control_passed']
    else:
        assert '** Fatal:' not in log and 'Errors: 0, Warnings: 0' in log
        assert log.count('PASS SERVICE_CONTROL') == 1
        assert 'good=3 pix_id=3 pixels=552960 peak=2' in log
        assert r['control_passed'] and not r['target_reproduced']
    runs[label] = r
files = ['prepare_service_bench.py', 'run_service.py', 'finalize.py', 'tb_service_starvation.sv', 'bench_binding.json', 'REPORT.md']
for label in runs:
    files += [f'{label}/{name}' for name in ['result.json', 'execution.json', 'step0.log', 'step1.log', 'step2.log', 'tb_service_starvation.sv', *runs[label]['production_sha256']]]
record = {'package': str(PACKAGE), 'package_bit_sha256': q['bitstream_sha256'],
          'qualification_sha256': sha(PACKAGE/'release/qualification.json'),
          'scope': binding['scope'], 'runs': runs,
          'files_sha256': {name: sha(ROOT/name) for name in files},
          'excluded_prototype': 'control: initial independent bench declaration-order compile error; preserved, not production evidence'}
(ROOT/'verification.json').write_text(json.dumps(record, indent=2)+'\n')
print('PASS offline binding: 2 runs, 45 production sources each, exact command/log hashes; control pass and expected red fatal verified')
