"""Bind only actual completed isolated writer experiments; no simulation launch."""
from pathlib import Path
import difflib,hashlib,json,re
R=Path(__file__).resolve().parent
OLD=Path('D:/FPGA/deliveries/FullHD_Lens_IntegratedRepair_20261023/sources/continuous_capture_writer.v')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def require(v,m):
 if not v:raise RuntimeError(m)
negative={'old_red_final','old_limit_final','new_limit_final','rate_old_final'}
names=['old_red_final','new_green_final','old_limit_final','new_limit_final','rate_old_final','rate_new_final',
       'control0_final2','control1_final2','control2_final2','control3_final2','multi_final2','reset_final2','lifecycle_final']
files={};records={}
for name in names:
 d=R/name;v=json.loads((d/'verification.json').read_text());require(v['matched'],name)
 bench='tb_writer_lifecycle.sv' if name=='lifecycle_final' else 'tb_writer_overlap.sv'
 require(v['bench_sha256']==sha(R/bench)==sha(d/bench),'bench drift '+name)
 expected=OLD if name.startswith('old_') or name=='rate_old_final' else R/'continuous_capture_writer.v'
 require(v['rtl_sha256']==sha(expected)==sha(d/'continuous_capture_writer.v'),'RTL drift '+name)
 for i,c in enumerate(v['commands']):
  log=d/f'step{i}.log';t=log.read_text()
  require(sha(log)==c['log_sha256'],'log drift '+name)
  if i<2:require(c['exit_code']==0 and '** Error:' not in t and '** Fatal:' not in t and '** Warning:' not in t,'compile '+name)
  if i==1:require('Errors: 0, Warnings: 0' in t,'compile summary '+name)
 text=(d/'step2.log').read_text()
 if name in negative:
  require('** Fatal: BOUNDED_QUEUE_OVERFLOW' in text and 'Warnings: 0' in text,'negative '+name)
 else:
  require(v['commands'][2]['exit_code']==0 and 'Errors: 0, Warnings: 0' in text and '** Fatal:' not in text and '** Error:' not in text,'positive '+name)
  require(('PASS lifecycle' if name=='lifecycle_final' else 'PASS writer bounded16') in text,'PASS '+name)
 records[name]=dict(expected_negative=name in negative,record=v,summary=[s for s in text.splitlines() if 'PASS ' in s or '** Fatal:' in s])
 for f in [d/'continuous_capture_writer.v',d/bench,d/'verification.json',*(d/f'step{i}.log' for i in range(3))]:files[f.relative_to(R).as_posix()]=sha(f)
(R/'rtl.diff').write_text(''.join(difflib.unified_diff(OLD.read_text().splitlines(True),(R/'continuous_capture_writer.v').read_text().splitlines(True),fromfile='c129/continuous_capture_writer.v',tofile='overlap/continuous_capture_writer.v')))
for name in ['continuous_capture_writer.v','tb_writer_overlap.sv','tb_writer_lifecycle.sv','run.py','finalize.py','DESIGN.md','rtl.diff']:files[name]=sha(R/name)
out=dict(scope='Isolated writer client contract; not physical/native engine integration qualification',
 old_source=str(OLD),old_sha256=sha(OLD),new_sha256=sha(R/'continuous_capture_writer.v'),
 positive_runs=9,expected_bounded_queue_failures=4,runs=records,files_sha256=files,
 prototype_failures_excluded=['control1: final-ACK coverage invalid for discarded last partial burst'],
 unchanged_production_candidate='D:/FPGA/output/live_repair_20261024/candidate_v2')
(R/'verification.json').write_text(json.dumps(out,indent=2)+'\n')
print('PASS evidence binding',len(files),'files, 9 positive, 4 intentional bounded-queue failures')
