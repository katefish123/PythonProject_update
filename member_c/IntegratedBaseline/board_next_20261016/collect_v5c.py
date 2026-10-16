"""Collect exact-source V5C functional evidence; implementation is qualified separately."""
from pathlib import Path
import hashlib,json,re,shutil
H=Path(__file__).resolve().parent
E=H/'evidence/v5c';E.mkdir(parents=True,exist_ok=True)
F=Path('D:/FPGA/output/c_board_next_v5c_20261016')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):
 b=p.read_bytes();return b.decode('utf-16' if b.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8-sig')
m=json.loads((F/'freeze_manifest.json').read_text())
for group in ('designs','constraints'):
 for p,d in m['original_inputs'][group].items():assert sha(Path(p))==d,('current drift',p)
for p,d in m['frozen_inputs'].items():assert sha(Path(p))==d,('frozen drift',p)
frozen={Path(p).name:d for p,d in m['frozen_inputs'].items()}
tests={
 'raw_native12':'c_board_next_raw_20261016_v5b_raw12',
 'raw_rgb_native12':'c_board_next_raw_20261016_v5c_rgb12',
 'corrected_native6':'c_board_next_raw_20261016_v5b_corrected6',
 'raw_phase':'c_board_next_raw_20261016_window_phase2',
 'corrected_quads':'c_board_next_raw_20261016_window_quads',
 'display_budget':'c_board_next_display_20261016_window_budget',
 'display_late':'c_board_next_display_20261016_window_late',
 'board_recovery':'c_board_recovery_integration_20261016_v5c_source_recovery',
 'observers':'c_board_next_observers_20261016_same_edge_green2',
 'legacy_counterexample':'c_color_geometry_20261016_actual_roi_counterexample',
}
summary={'hardware_accepted':False,'functional_evidence_does_not_qualify_physical_timing':True,
 'physical_timing_receipt':'implementation.json',
 'scope':'V5C final application, board integration, observers and coordinated recovery',
 'tests':{},'frozen_inputs':m,'limitations':[
 'Functional native memory model does not model physical DDR training, DQS or DRAM refresh.',
 'RAW simulation reaches about30 new images/s; camera hardware throughput not measured.',
 'FullHD correction pixel tests do not establish60 new corrected images/s.',
 'Physical blur, OVER and PHY alignment root cause require hardware acceptance.']}
for name,folder in tests.items():
 src=Path('D:/FPGA/output')/folder;dst=E/name;dst.mkdir(exist_ok=True)
 passes=[];logs={}
 for p in src.glob('*.log'):
  t=read(p);assert not re.search(r'\*\* (?:Fatal|Error|Warning):',t),(name,p.name)
  assert not re.search(r'Errors:\s*[1-9]|Warnings:\s*[1-9]',t),(name,p.name)
  passes+=re.findall(r'PASS [^\r\n]+',t)
  shutil.copyfile(p,dst/p.name);logs[p.name]=sha(p)
 assert passes,('missing PASS',name)
 compiled={p.name:sha(p) for p in (src/'source_snapshot').glob('*') if p.is_file()}
 matched=[]
 for p,d in compiled.items():
  if p in frozen:
   assert d==frozen[p],('compiled production source drift',name,p)
   matched.append(p)
 if name in ('raw_native12','raw_rgb_native12','corrected_native6'):
  app=json.loads((H/'integration/source_manifest.json').read_text())['sources']
  for p,d in app.items():assert compiled[Path(p).name]==d,('application snapshot',name,p)
 if name=='board_recovery':
  for p in ('video_correct_ddr_top.v','native_service_monitor.v','board_recovery_reset.v'):
   assert p in matched,('missing actual board source',p)
 summary['tests'][name]={'output_directory':src.as_posix(),'passes':passes,
  'logs_sha256':logs,'compiled_snapshot_sha256':compiled,'matched_final_pds_sources':matched}
raw=read(Path('D:/FPGA/output')/tests['raw_native12']/'simulation.log')
times=[int(t) for t in re.findall(r'PIPELINE_PUBLICATION.*?time=(\d+)',raw)]
intervals=[(b-a)/1000 for a,b in zip(times,times[1:])]
summary['raw_publication_intervals_ns']=intervals
summary['raw_steady_new_images_per_second']=len(intervals[-8:])*1e9/sum(intervals[-8:])
assert 29.99<summary['raw_steady_new_images_per_second']<30.01
bit=H.parent/'stream_video_20261015/release_candidate_v4s/video_correct_ddr_top.sbit'
assert sha(bit)=='3e3475d30e6fa2488a57a084aa236353077b91d80969b7d1c412c89c064d1b50'
summary['unchanged_v4s_sbit_sha256']=sha(bit)
(E/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print('PASS V5C exact-source evidence:',len(tests),'groups; RAW',summary['raw_steady_new_images_per_second'],'new images/s;146 PDS inputs unchanged')
