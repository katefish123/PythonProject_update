"""Verify the actual native control evidence without running simulation."""
from pathlib import Path
import hashlib,json,re
ROOT=Path(__file__).resolve().parent
PACKAGE=Path('D:/FPGA/deliveries/FullHD_Lens_IntegratedRepair_20261023')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
v=json.loads((ROOT/'control/result.json').read_text())
e=json.loads((ROOT/'control/execution.json').read_text())
b=json.loads((ROOT/'bench_binding.json').read_text())
q=json.loads((PACKAGE/'release/qualification.json').read_text())
assert all(v[k]==x for k,x in e.items())
assert v['control_passed'] and not v['target_reproduced']
assert len(v['production_sha256'])==45
assert v['qualification_sha256']==sha(PACKAGE/'release/qualification.json')
assert v['package_bit_sha256']==q['bitstream_sha256']
assert v['runner_sha256']==sha(ROOT/'run_service.py')
assert v['bench_binding_sha256']==sha(ROOT/'bench_binding.json')
for n,h in v['production_sha256'].items():
    assert sha(ROOT/'control'/n)==h
    expected=sha(ROOT/'continuous_capture_writer.v') if n=='continuous_capture_writer.v' else q['candidate_source_sha256'][n]
    assert h==expected
assert sha(ROOT/'continuous_capture_writer.v')=='3c2a41136b9729a7a19df52158bfa5e942b0cf677a2bf0a1e035e04fd5f94ff0'
assert sha(Path(b['parent_bench']))==b['parent_bench_sha256']
s=Path(b['parent_bench']).read_text()
for old,new in b['changes']:
    assert s.count(old)==1
    s=s.replace(old,new)
assert s==(ROOT/'tb_service_starvation.sv').read_text()
assert sha(ROOT/'tb_service_starvation.sv')==sha(ROOT/'control/tb_service_starvation.sv')==b['generated_bench_sha256']==v['bench_sha256']
assert v['commands'][1]['args']==['vlog.exe','-sv',*v['production_sha256'],'tb_service_starvation.sv']
assert v['commands'][2]['args']==['vsim.exe','-c','-voptargs=+acc','-gADVERSE=0','tb_service_starvation','-do','run -all;quit -f']
for i,c in enumerate(v['commands']):
    assert c['exit_code']==0 and sha(ROOT/'control'/f'step{i}.log')==c['log_sha256']
    log=(ROOT/'control'/f'step{i}.log').read_text()
    assert not re.search(r'\*\* (Fatal|Error|Warning):',log)
log=(ROOT/'control/step2.log').read_text()
assert 'Errors: 0, Warnings: 0' in log
assert log.count('PASS SERVICE_CONTROL')==1
assert 'physical=7 good=3 pix_id=3 pixels=8294400 peak=2' in log
assert len(re.findall(r'CAPTURE_CLOSE gen=\d+ ok=1 reason=0',log))==3
files=['REPORT.md','finalize.py','preparation.json','run_service.py','continuous_capture_writer.v','tb_service_starvation.sv','bench_binding.json','control/result.json','control/execution.json',*[f'control/step{i}.log' for i in range(3)],*[f'control/{n}' for n in v['production_sha256']],'control/tb_service_starvation.sv']
(ROOT/'verification.json').write_text(json.dumps({'status':'native1920x1080 RAW shared-core control passed','scope':b['scope'],'run':v,'files_sha256':{n:sha(ROOT/n) for n in files}},indent=2)+'\n')
print('PASS offline native binding: 45 RTL, exactly writer replacement, exact fixture transform/argv/logs, 8294400 golden pixels, 0 errors/warnings')
