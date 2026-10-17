"""Bind old/new schedule equivalence and mapping pixels to actual source bytes."""
from pathlib import Path
import hashlib,json,re,zipfile
H=Path(__file__).resolve().parent;B=H.parent/'lens_model_next';E=H/'evidence';E.mkdir(exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):
 b=p.read_bytes();return b.decode('utf-16' if b.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8-sig')
baseline=json.loads((B/'verification.json').read_text())
assert all(sha(B/n)==d for n,d in baseline['source_sha256'].items()),'original numeric baseline changed'
derived=json.loads((H/'generated/source_manifest.json').read_text())
for n,d in derived.items():
 assert sha(B/n)==d['baseline_sha256']
 assert sha(H/'generated'/(Path(n).stem+'_fast.v'))==d['derived_sha256']
records={};archive=E/'exact_schedule_tests.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
 for key,suffix in [('equivalence','equivalence_v2'),('brown','brown_v2'),('composed','composed_v2'),('old_schedule_negative','old_schedule_v2_red')]:
  p=Path('D:/FPGA/output/lens_fast_20261017_'+suffix);log=read(p/'simulation.log')
  negative=key.endswith('negative')
  assert 'Errors: 0, Warnings: 0' in read(p/'compile.log')
  if negative:assert '** Fatal: FAST_DIV_STILL_ITERATES_UNNEEDED_BITS' in log
  else:
   assert 'PASS ' in log and 'Errors: 0, Warnings: 0' in log
   assert sha(p/'source_snapshot/q30_alu_fast.v')==sha(H/'q30_alu_fast.v')
   if key!='equivalence':
    for n,d in derived.items():assert sha(p/'source_snapshot'/(Path(n).stem+'_fast.v'))==d['derived_sha256']
    fm=json.loads((p/'fixtures/manifest.json').read_text())
    for n,field in [('vectors.hex','vectors_sha256'),('composed_vectors.hex','composed_vectors_sha256'),('expected_pixels.hex','expected_pixels_sha256')]:
     assert sha(p/'fixtures'/n)==fm[field]
  record={'output_directory':p.as_posix(),'expected_failure':negative,'compile_log_sha256':sha(p/'compile.log'),
   'simulation_log_sha256':sha(p/'simulation.log'),'compiled_source_sha256':{f.name:sha(f) for f in (p/'source_snapshot').iterdir()}}
  if 'max_cycles=' in log:record['max_cycles']=int(re.search(r'max_cycles=(\d+)',log)[1])
  if key=='equivalence':record['statistics']={name:int(re.search(name+r'=(\d+)',log)[1]) for name in ('cases','max_fast_div_cycles','old_div_cycles_sum','fast_div_cycles_sum')}
  records[key]=record
  for n in ('compile.log','simulation.log','compiled_hashes.json'):z.write(p/n,key+'/'+n)
  for folder in ('source_snapshot','fixtures'):
   if (p/folder).exists():
    for f in (p/folder).iterdir():z.write(f,key+'/'+folder+'/'+f.name)
old_brown=baseline['tests']['brown_pixels']['maximum_cycles'];old_composed=baseline['tests']['composed_pixels']['maximum_cycles']
summary={'scope':'synthetic exact scheduling optimization,not board/physical optics/video qualification',
 'enterprise_acceptance':False,'hardware_acceptance':False,'board_integrated':False,'board_timing_qualified':False,
 'real_calibration':'blocked_by_missing_calibration','tests':records,
 'comparison':{'brown_old_max_cycles':old_brown,'brown_new_max_cycles':records['brown']['max_cycles'],
  'composed_old_max_cycles':old_composed,'composed_new_max_cycles':records['composed']['max_cycles'],
  'note':'Maximum observed cycles on identical1024 synthetic vectors; no conversion to hardware frames/s.'},
 'original_numeric_baseline_receipt_sha256':sha(B/'verification.json'),
 'source_sha256':{p.relative_to(H).as_posix():sha(p) for p in [H/'q30_alu_fast.v',H/'tb_div_equivalence.sv',H/'build_fast.py',H/'run_tests.ps1']+list((H/'generated').glob('*.v'))},
 'archive_sha256':sha(archive)}
assert records['brown']['max_cycles']<old_brown and records['composed']['max_cycles']<old_composed
(H/'verification.json').write_text(json.dumps(summary,indent=2)+'\n')
print('PASS exact-schedule evidence:',summary['comparison'])
