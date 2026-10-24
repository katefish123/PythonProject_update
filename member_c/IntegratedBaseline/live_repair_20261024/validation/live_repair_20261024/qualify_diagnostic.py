"""Gate exact diagnostic-only delta; never claims repair or optical acceptance."""
from pathlib import Path
import argparse,hashlib,json,re,shutil
if not __debug__:raise RuntimeError('Qualification refuses optimized Python: safety assertions must remain enabled')
from diagnostic_transform import transform
ap=argparse.ArgumentParser();ap.add_argument('--repair',action='store_true');ap.add_argument('--implementation',choices=['build','performance','final_check'],default='build');args=ap.parse_args()
r=Path(__file__).resolve().parent;c=r/('candidate_repair' if args.repair else 'candidate_v2');parent=Path('D:/FPGA/deliveries/FullHD_Lens_Acceptance_20261024')
assert args.implementation=='final_check','Release requires explicit same-DB independent STA and bitgen'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
read=lambda p:p.read_text(encoding='utf-8-sig',errors='replace')
m=json.loads(read(c/'source_manifest.json'));pq=json.loads(read(parent/'release/qualification.json'))
for name,h in m['candidate_source_sha256'].items():
 assert sha(c/'sources'/name)==h,'Candidate source drift '+name
 if name!='video_correct_ddr_top.v' and not(args.repair and name=='continuous_capture_writer.v'):assert sha(parent/'sources'/name)==h,'Unexpected functional source delta '+name
top=read(c/'sources/video_correct_ddr_top.v');old=read(parent/'sources/video_correct_ddr_top.v')
assert top==transform(old),'Top differs beyond exact reviewed diagnostic transformation'
# External top declaration and all physical constraints remain byte-identical.
assert top[:top.index(' wire clocks_ready')]==old[:old.index(' wire clocks_ready')]
assert sha(c/'sources/board_ddr.fdc')==sha(parent/'sources/board_ddr.fdc')
assert 'assign overlay_on=status_on||telemetry_on;' in top
test=r/'observer_sim_v3/step2.log'
assert 'PASS LIVE_DIAGNOSTIC_OBSERVERS' in read(test) and 'Errors: 0, Warnings: 0' in read(test)
bound=read(r/'observer_sim_v3/tb.sv');block=top[top.index(' // Read-only diagnosis;'):top.index(' wire[1919:0]trace_data;')]
assert block in bound,'Observed RTL differs from tested block'
if args.repair:
 assert sha(c/'sources/video_correct_ddr_top.v')==sha(r/'candidate_v2/sources/video_correct_ddr_top.v')
 experiments=r/'writer_overlap';v=json.loads(read(experiments/'verification.json'))
 assert sha(c/'sources/continuous_capture_writer.v')==v['new_sha256']
 assert v['positive_runs']==9 and v['expected_bounded_queue_failures']==4
 for name,h in v['files_sha256'].items():assert sha(experiments/name)==h,'Writer evidence drift '+name
 for record in v['runs'].values():assert record['record']['matched']
 native=r/'service_overlap_native/control';nr=json.loads(read(native/'result.json'))
 assert nr['control_passed']
 for name,h in nr['production_sha256'].items():assert sha(c/'sources'/name)==h and sha(native/name)==h
 for i,command in enumerate(nr['commands']):assert command['exit_code']==0 and sha(native/f'step{i}.log')==command['log_sha256']
 assert sha(native/'tb_service_starvation.sv')==nr['bench_sha256']
 assert 'pixels=8294400' in read(native/'step2.log') and 'Errors: 0, Warnings: 0' in read(native/'step2.log')
 corrected=r/'service_overlap_corrected'
 # This gate deliberately refuses prepared-only fixtures or old writer runs.
 assert corrected.is_dir(),'Corrected regression missing'
 cv=json.loads(read(corrected/'verification.json'));assert cv['passed'] and cv['exit_code']==0
 for name,h in cv['logs_sha256'].items():assert sha(corrected/name)==h,'Corrected log drift '+name
 assert sha(corrected/'source_snapshot/tb_lens_board.sv')==cv['bench_sha256']
 for name,h in cv['fixtures_sha256'].items():assert sha(Path(name))==h,'Corrected fixture drift '+name
 cl=read(corrected/'simulation.log');assert 'PASS RAW_PIPELINE corrected=1 native=1' in cl and 'pixels=14515200 unique_scans=2 published=2' in cl and 'Errors: 0, Warnings: 0' in cl
 for f in (corrected/'source_snapshot').iterdir():
  if f.name!='tb_lens_board.sv':assert sha(c/'sources'/f.name)==sha(f),'Corrected test source mismatch '+f.name
b=c/args.implementation
if args.implementation!='build':
 binding=json.loads(read(b/'input_binding.json'));assert sha(c/'source_manifest.json')==binding['candidate_manifest_sha256']
 assert sha(c/'build.tcl')==binding['upstream_build_tcl_sha256'] and sha(b/'route.tcl')==binding['route_tcl_sha256']
 for name,record in binding['inputs'].items():assert sha(Path(name))==record['sha256']==sha(Path(record['upstream']))
 assert binding['compiled_inputs']==m['candidate_source_sha256']
 db=Path(binding['same_explicit_db_for_sta_and_bitgen']);assert str(db) in binding['inputs']
 script=read(b/'route.tcl')
 for cmd in ['report_timing','gen_bit_stream']:assert cmd+' -force_to_run -input_db_file {'+db.as_posix()+'}' in script
 execution=json.loads(read(b/'execution.json'));assert execution['exit_code']==0 and execution['input_binding_sha256']==sha(b/'input_binding.json') and execution['script_sha256']==sha(b/'route.tcl')
 assert execution['log_sha256']==sha(b/'pds_console.log')
 assert execution['timing_worker_exit_code']==0 and execution['timing_worker_log_sha256']==sha(b/'report_direct.log')
 assert execution['timing_project_after_sha256']==sha(b/'route.pds') and execution['timing_input_db_sha256']==sha(db)
 assert execution['timing_worker_argv']==['D:/softwares/PDS/PDS_2022.2-SP6.4/bin/pds_shell.exe','-action','report_timing','-project_file',str(b/'route.pds')]
 assert 'Report timing is finished successfully.' in read(b/'report_direct.log')
 upstream_logs=[v for name,v in binding['inputs'].items() if name.endswith('upstream_pds_console.log')]
 assert len(upstream_logs)==1 and upstream_logs[0]['sha256']==binding['upstream_implementation_log_sha256']
log=read(c/'pds_console.log' if args.implementation=='build' else b/'pds_console.log');assert 'Process "Generate Bitstream" done.' in log and not re.search(r'^E:|ERROR:',log,re.M),'PDS incomplete/error'
reports=list(b.glob('video_correct_ddr_top.rtr'));assert len(reports)==1
report=reports[0];text=read(report)
assert 'Design Summary : All Constraints Met.' in text,'Final timing failed'
sections=re.findall(r'(?:Setup|Hold|Recovery|Removal|Minimum Pulse Width) Summary\((?:Slow|Fast) Corner\):\s*\n(.*?)(?=\n\s*\n)',text,re.S)
assert len(sections)==10;rows=[]
for section in sections:
 for line in section.splitlines():
  v=re.search(r'(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*$',line)
  if v:assert float(v[1])>=0 and int(v[3])==0,line;rows.append(line.strip())
assert len(rows)==100
domains=lambda rs:[re.sub(r'\s+-?\d+\.\d+\s+-?\d+\.\d+\s+\d+\s+\d+\s*$','',v).split() for v in rs]
assert domains(rows)==domains(pq['timing_summary_rows']),'Clock coverage changed'
bit=b/'generate_bitstream/video_correct_ddr_top.sbit';mask=bit.with_suffix('.smsk')
assert bit.stat().st_size>1000000 and mask.stat().st_size>0
out=c/'release';out.mkdir(exist_ok=False)
for f in (bit,mask):shutil.copyfile(f,out/f.name)
q={'fixtures':pq['fixtures'],'ancestor_qualification':pq}
q.update(candidate_source_sha256=m['candidate_source_sha256'],bitstream=str(out/bit.name),mask=str(out/mask.name),bitstream_sha256=sha(bit),mask_sha256=sha(mask),final_timing_report=str(report),final_timing_sha256=sha(report),timing_summary_rows=rows,timing_qualified=True,ready_for_authorized_cram_experiment=True,hardware_programmed=False,real_video_acceptance=False,white_gray_resolved=False,scope='Diagnostic-only candidate; unchanged functional pipeline; no repair claim',parent_qualification_sha256=sha(parent/'release/qualification.json'),diagnostic_observer_sim_sha256=sha(test),functional_source_change=False)
q['reused_full_chain_evidence']='Parent display_regressions reused only for unchanged functional modules; no claim diagnostic top was in those runs'
q['implementation']=args.implementation
q['diagnostic_transform_sha256']=sha(r/'diagnostic_transform.py')
q['implementation_log_sha256']=sha(c/'pds_console.log' if args.implementation=='build' else b/'pds_console.log')
q['source_manifest_sha256']=sha(c/'source_manifest.json')
q['implementation_artifacts_sha256']={str(p):sha(p) for p in [b/'input_binding.json',b/'execution.json',b/'route.tcl',b/'route.pds',db,b/'report_direct.log',b/'generate_bitstream/run.log']}
q['implementation_artifacts_sha256'].update({name:v['sha256'] for name,v in binding['inputs'].items()})
q['white_gray_hardware_problem_resolved']=False
q['current_changed_datapath_modules']=['video_correct_ddr_top.v']+(['continuous_capture_writer.v'] if args.repair else [])
q['current_full_chain_evidence']=['native_raw','native_corrected'] if args.repair else []
q['display_regressions']={} if args.repair else pq['display_regressions']
if args.repair:
 q.update(functional_source_change=True,scope='Double-assembly capture writer plus always-visible diagnostics; native RAW and corrected regressions; live repair not accepted',writer_evidence_sha256=sha(experiments/'verification.json'),native_raw_log_sha256=sha(native/'step2.log'),native_corrected_log_sha256=sha(corrected/'simulation.log'))
 q['display_regressions']['native_corrected']={'directory':str(corrected),'source_subdirectory':'source_snapshot','simulation_sha256':sha(corrected/'simulation.log'),'compile_sha256':sha(corrected/'compile.log'),'testbench_name':'tb_lens_board.sv','testbench_sha256':cv['bench_sha256'],'production_sha256':{n:v['candidate_sha256'] for n,v in cv['source_binding'].items() if v['candidate_sha256'] is not None},'pass_token':'PASS RAW_PIPELINE corrected=1 native=1 pixels=14515200 unique_scans=2 published=2'}
q['qualification_evidence_sha256']={'observer_sim_v3/step2.log':sha(test),'diagnostic_transform.py':sha(r/'diagnostic_transform.py')}
if args.repair:q['qualification_evidence_sha256'].update({'writer_overlap/verification.json':sha(experiments/'verification.json'),'service_overlap_native/control/step2.log':sha(native/'step2.log'),'service_overlap_corrected/simulation.log':sha(corrected/'simulation.log')})
for folder in ['observer_sim_v3']+(['writer_overlap','service_overlap_native','service_overlap_corrected'] if args.repair else []):
 for f in (r/folder).rglob('*'):
  if f.is_file() and not any(x in ('work','__pycache__') for x in f.relative_to(r).parts):q['qualification_evidence_sha256'][f.relative_to(r).as_posix()]=sha(f)
q['external_evidence_sha256']=cv['fixtures_sha256'] if args.repair else {}
(out/'qualification.json').write_text(json.dumps(q,indent=2)+'\n')
print('DIAGNOSTIC_TIMING_QUALIFIED '+sha(bit))
