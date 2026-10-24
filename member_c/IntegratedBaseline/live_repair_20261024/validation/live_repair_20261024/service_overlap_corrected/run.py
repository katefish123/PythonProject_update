"""Invoke the unchanged original PowerShell regression, one ModelSim instance."""
from pathlib import Path
import hashlib,json,subprocess,time
ROOT=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
p=json.loads((ROOT/'preparation.json').read_text())
for n,r in p['source_binding'].items():
    assert sha(ROOT/'source_snapshot'/n)==r['run_sha256']
    if r['candidate_sha256'] is not None:
        assert sha(Path(p['candidate_sources'])/n)==r['candidate_sha256']
for name,h in p['fixtures_sha256'].items():assert sha(Path(name))==h
assert sha(ROOT/'run.ps1')==p['run_ps1_sha256']
argv=['direct ModelSim invocation equivalent to unchanged run.ps1']
t=time.time()
commands=[['vlib.exe','work'],['vlog.exe','-sv',*[str(f) for f in sorted((ROOT/'source_snapshot').iterdir()) if f.is_file()]],['vsim.exe','-c','-do','onfinish stop;run -all;quit -f','work.tb_raw_pipeline']]
actual=[]
for logfile,cmd in zip(['library.log','compile.log','simulation.log'],commands):
    cmd[0]='D:/softwares/modelsim/win64/'+cmd[0]
    with (ROOT/logfile).open('w') as log:
        proc=subprocess.run(cmd,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
    actual.append({'argv':cmd,'exit_code':proc.returncode,'log_sha256':sha(ROOT/logfile)})
    if proc.returncode:break
(ROOT/'runner.log').write_text(json.dumps(actual,indent=2)+'\n')
logs=['library.log','compile.log','simulation.log','runner.log']
v={'argv':argv,'cwd':str(ROOT),'exit_code':proc.returncode,'elapsed_seconds':time.time()-t,'runner_sha256':sha(Path(__file__)),'preparation_sha256':sha(ROOT/'preparation.json'),'logs_sha256':{n:sha(ROOT/n) for n in logs},'source_binding':p['source_binding'],'bench_sha256':p['bench_sha256'],'fixtures_sha256':p['fixtures_sha256'],'run_ps1_sha256':p['run_ps1_sha256']}
log=(ROOT/'simulation.log').read_text()
v['observations']=[l for l in log.splitlines() if 'PASS RAW_PIPELINE' in l or 'PUBLICATION' in l or 'Errors:' in l]
v['passed']=proc.returncode==0 and log.count('PASS RAW_PIPELINE corrected=1 native=1')==1 and 'Errors: 0, Warnings: 0' in log and '** Fatal:' not in log and '** Error:' not in log and '** Warning:' not in log
(ROOT/'verification.json').write_text(json.dumps(v,indent=2)+'\n')
print('\n'.join(v['observations']))
if not v['passed']:raise RuntimeError('Actual corrected regression failed; inspect preserved logs')
