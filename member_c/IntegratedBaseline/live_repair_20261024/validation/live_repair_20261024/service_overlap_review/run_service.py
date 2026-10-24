from pathlib import Path
import hashlib,json,re,subprocess,sys
ROOT=Path(__file__).resolve().parent
PACKAGE=Path('D:/FPGA/deliveries/FullHD_Lens_IntegratedRepair_20261023')
mode=sys.argv[1];branch=mode.split('_')[0]
if branch not in ('control','adverse'):raise ValueError(mode)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
out=ROOT/mode;out.mkdir(exist_ok=False)
q=json.loads((PACKAGE/'release/qualification.json').read_text())
names=[p.name for p in (PACKAGE/'validation/baseline_test/source_snapshot').glob('*.v')]
if len(names)!=45:raise RuntimeError('Unexpected source set')
for name in names:
 p=PACKAGE/'sources'/name
 if sha(p)!=q['candidate_source_sha256'][name]:raise RuntimeError('Production hash drift '+name)
 replacement=ROOT/'continuous_capture_writer.v'
 if name=='continuous_capture_writer.v':
  if sha(replacement)!='3c2a41136b9729a7a19df52158bfa5e942b0cf677a2bf0a1e035e04fd5f94ff0':raise RuntimeError('Frozen overlap RTL drift')
  (out/name).write_bytes(replacement.read_bytes())
 else:(out/name).write_bytes(p.read_bytes())
(out/'tb_service_starvation.sv').write_bytes((ROOT/'tb_service_starvation.sv').read_bytes())
args=[['vlib.exe','work'],['vlog.exe','-sv',*names,'tb_service_starvation.sv'],
 ['vsim.exe','-c','-voptargs=+acc','-gADVERSE='+str(int(branch=='adverse')),'tb_service_starvation','-do','run -all;quit -f']]
record={'mode':mode,'package_bit_sha256':q['bitstream_sha256'],'qualification_sha256':sha(PACKAGE/'release/qualification.json'),
 'production_sha256':{n:sha(out/n) for n in names},'bench_sha256':sha(out/'tb_service_starvation.sv'),
 'runner_sha256':sha(Path(__file__)),'bench_binding_sha256':sha(ROOT/'bench_binding.json'),'commands':[]}
for i,a in enumerate(args):
 r=subprocess.run([str(Path('D:/softwares/modelsim/win64')/a[0]),*a[1:]],cwd=out,capture_output=True,text=True)
 log=out/f'step{i}.log';log.write_text(r.stdout+r.stderr)
 record['commands'].append({'args':a,'exit_code':r.returncode,'log_sha256':sha(log)})
 (out/'execution.json').write_text(json.dumps(record,indent=2)+'\n')
 if i<2 and (r.returncode or re.search(r'\*\* (Error|Fatal|Warning):',log.read_text())):raise RuntimeError(str(log))
text=(out/'step2.log').read_text()
record['observations']=[l for l in text.splitlines() if any(x in l for x in ('PASS SERVICE','SERVICE_','DISPLAY_FAILURE','REJECT total','CAPTURE_CLOSE','PIPELINE_PUBLICATION'))]
record['target_reproduced']='** Fatal: SERVICE_STARVATION_REPRO' in text
record['control_passed']='PASS SERVICE_CONTROL' in text and '** Fatal:' not in text
(out/'result.json').write_text(json.dumps(record,indent=2)+'\n')
print('\n'.join(record['observations']))
if branch=='control' and not record['control_passed']:raise RuntimeError('Control failed')
if branch=='adverse' and not record['target_reproduced']:raise RuntimeError('Target not reproduced; inspect actual evidence')
