"""Archive synthetic numeric baseline, not enterprise/board acceptance."""
from pathlib import Path
import hashlib,json,re,zipfile
H=Path(__file__).resolve().parent
E=H/'evidence';E.mkdir(exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):
 b=p.read_bytes();return b.decode('utf-16' if b.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8-sig')
tests={'alu':'alu_final','profile_bank':'bank_final','brown_pixels':'brown_final','composed_pixels':'composed_final'}
records={};archive=E/'synthetic_numeric_evidence.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
 for key,suffix in list(tests.items())+[(f'missing_term_{i}',f'final_missing_term_{i}') for i in range(1,5)]:
  p=Path('D:/FPGA/output/lens_rtl_20261017_'+suffix)
  log=read(p/'simulation.log');compile_log=read(p/'compile.log')
  negative=key.startswith('missing_term_')
  assert 'Errors: 0, Warnings: 0' in compile_log
  if negative:assert '** Fatal: Brown vector' in log
  else:assert 'PASS ' in log and 'Errors: 0, Warnings: 0' in log and not re.search(r'\*\* (Error|Fatal|Warning):',log)
  compiled={f.name:sha(f) for f in (p/'source_snapshot').iterdir()}
  for f in H.glob('*.v'):assert compiled[f.name]==sha(f),('production drift',key,f.name)
  if (p/'fixtures').exists():
   m=json.loads((p/'fixtures/manifest.json').read_text())
   for n,field in [('vectors.hex','vectors_sha256'),('composed_vectors.hex','composed_vectors_sha256'),('expected_pixels.hex','expected_pixels_sha256')]:
    assert sha(p/'fixtures'/n)==m[field],('fixture drift',key,n)
   for n,d in m['reference_sha256'].items():assert sha(H.parent/'lens_model_20261015'/n)==d
   assert sha(H/'prepare_vectors.py')==m['generator_sha256']
   assert sha(H/'corner_preparation.py')==m['corner_preparation_sha256']
   assert any(abs(v)>1e-8 for v in m['synthetic_inverse_corner_H_case']['ideal_H'][6:8])
  for name in ('source_snapshot','fixtures'):
   if (p/name).exists():
    for f in (p/name).iterdir():z.write(f,key+'/'+name+'/'+f.name)
  for n in ('compile.log','simulation.log','compiled_hashes.json'):z.write(p/n,key+'/'+n)
  records[key]={'source_directory':p.as_posix(),'expected_failure':negative,'compiled_source_sha256':compiled,
   'simulation_log_sha256':sha(p/'simulation.log'),'reported_pass':re.findall(r'PASS [^\r\n]+',log)}
  if not negative and 'max_cycles=' in log:records[key]['maximum_cycles']=int(re.search(r'max_cycles=(\d+)',log)[1])
 z.write(H/'corner_tests.log','corner_tests.log')
 z.write(H/'corner_preparation.py','corner_preparation.py');z.write(H/'test_corner_preparation.py','test_corner_preparation.py')
manifest=json.loads(Path('D:/FPGA/output/lens_vectors_20261017/manifest.json').read_text())
summary={'status':'synthetic_numeric_baseline_pass','enterprise_acceptance':False,'hardware_acceptance':False,
 'real_calibration':'blocked_by_missing_calibration','PDS_timing_qualified':False,'board_integrated':False,
 'tests':records,'vectors':manifest,'archive_sha256':sha(archive),
 'source_sha256':{f.name:sha(f) for f in H.iterdir() if f.suffix in ('.v','.sv','.py','.ps1')},
 'scope':'Independent sequential H/Brown coordinates,complete synthetic parameter bank,original B sampling; no live video,physical optics or resource/timing qualification',
 'remaining':['Pipelined full-resolution throughput and resource/timing implementation.',
 'Integrated request/DDR/display ownership regression on changed board RTL.',
 'Measured camera calibration and disjoint held-out MTF/SFR/geometry/edge tests.',
 'Real calibration loader/provenance,global inverse-domain/monotonicity validation.']}
assert 'Ran 5 tests' in read(H/'corner_tests.log') and re.search(r'\bOK\s*$',read(H/'corner_tests.log'))
(H/'verification.json').write_text(json.dumps(summary,indent=2)+'\n')
print('PASS synthetic evidence:4 green RTL groups,4 intentional coefficient failures,5 host tests; real/board/timing acceptance=false')
