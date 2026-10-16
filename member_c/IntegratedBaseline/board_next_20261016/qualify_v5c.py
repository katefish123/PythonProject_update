"""Package only a completed, exact-input, all-constraints-met V5C implementation."""
from pathlib import Path
import hashlib,json,re,shutil,zipfile,subprocess
H=Path(__file__).resolve().parent
F=Path('D:/FPGA/output/c_board_next_v5c_20261016');B=F/'build'
E=H/'evidence/v5c';R=H/'release_candidate_v5c'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):
 b=p.read_bytes();return b.decode('utf-16' if b.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8-sig',errors='replace')
subprocess.run(['python',str(H/'collect_v5c.py')],check=True)
m=json.loads((F/'freeze_manifest.json').read_text())
log=read(F/'pds_stdout.log')
elapsed=re.findall(r'Action from compile to gen_bit_stream: Total Real Time elapsed is[^\r\n]*',log)
assert elapsed,'PDS full flow completion marker missing'
assert not re.search(r'^E:|ERROR:',log,re.M),'PDS error present'
reports=list(B.rglob('*.rtr'));assert len(reports)==1,('expected final timing report',reports)
t=read(reports[0]);assert 'Design Summary : All Constraints Met.' in t,'Timing failed'
for corner in ('Slow Corner','Fast Corner'):
 for check in ('Setup','Hold','Recovery','Removal','Minimum Pulse Width'):
  assert f'{check} Summary({corner}):' in t,('missing timing coverage',check,corner)
# Every summary data row has clock(s), slack, total slack, failing and total endpoints.
sections=re.findall(r'(?:Setup|Hold|Recovery|Removal|Minimum Pulse Width) Summary\((?:Slow|Fast) Corner\):\s*\n(.*?)(?=\n\s*\n)',t,re.S)
rows=[]
for section in sections:
 count=0
 for line in section.splitlines():
  match=re.search(r'(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*$',line)
  if match:
   fields=match.groups();assert float(fields[0])>=0 and int(fields[2])==0,('failing timing row',line)
   rows.append({'row':line.strip(),'slack_ns':float(fields[0]),'failing_endpoints':int(fields[2]),'total_endpoints':int(fields[3])});count+=1
 assert count>0,'empty timing summary'
assert len(sections)==10 and len(rows)>=90,('missing timing rows',len(sections),len(rows))
bits=list(B.rglob('*.sbit'));masks=list(B.rglob('*.smsk'))
assert len(bits)==len(masks)==1,(bits,masks)
assert bits[0].stat().st_size>1000000 and masks[0].stat().st_size>0
project=B/'build.pds';assert project.exists()
R.mkdir(exist_ok=True)
for p in bits+masks:shutil.copyfile(p,R/p.name)
shutil.copyfile(reports[0],E/'final_timing.rtr')
shutil.copyfile(F/'pds_stdout.log',E/'pds_stdout.log')
receipt={'candidate':'V5C','timing_qualified':True,'hardware_accepted':False,
 'burn_performed_by_this_task':False,'full_flow_completion':elapsed[-1],
 'input_count':len(m['frozen_inputs']),'timing_summary_rows_checked':len(rows),
 'timing_summary_rows':rows,
 'timing_report_sha256':sha(reports[0]),'build_log_sha256':sha(F/'pds_stdout.log'),
 'local_project':project.as_posix(),'local_root':F.as_posix(),
 'artifacts':{p.name:{'sha256':sha(p),'bytes':p.stat().st_size} for p in bits+masks},
 'frozen_inputs':m['frozen_inputs'],
 'limitations':['Hardware acceptance pending.','RAW30 simulation is not measured hardware performance.',
 'PHY root cause and real camera clarity remain unproven.','60 unique corrected frames/s not established.']}
(E/'implementation.json').write_text(json.dumps(receipt,indent=2)+'\n')
(R/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
portable='set root [file dirname [file normalize [info script]]]\n'
portable+='set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676\n'
for group,cmd in (('designs','add_design'),('constraints','add_constraint')):
 for p in m['original_inputs'][group]:portable+=f'{cmd} [file join $root sources {{{Path(p).name}}}]\n'
portable+='compile -top_module video_correct_ddr_top\nsynthesize -ads\ndev_map\npnr -gplace_seed 17 -groute_seed 17 -optimize_multi_corner_timing -slack_prior_in_global_router TRUE\nreport_timing\ngen_bit_stream\n'
# The portable script reproduces input/flow; a new implementation still needs its own timing check.
zip_path=R/'V5C_PDS_source_project.zip'
with zipfile.ZipFile(zip_path,'w',zipfile.ZIP_DEFLATED) as z:
 for p in (F/'sources').iterdir():z.write(p,'sources/'+p.name)
 z.writestr('build_portable.tcl',portable)
 z.write(project,'local_original/build.pds')
 z.write(F/'build.tcl','local_original/build.tcl')
 z.write(F/'freeze_manifest.json','freeze_manifest.json')
 for p in R.glob('*.sbit'):z.write(p,p.name)
 for p in R.glob('*.smsk'):z.write(p,p.name)
 z.write(R/'receipt.json','receipt.json');z.write(reports[0],'final_timing.rtr')
 z.write(H/'board/HANDOFF.md','HANDOFF.md')
 z.writestr('REBUILD.txt','Use PDS 2022.2-SP6.4. Create an empty build working directory, then run pds_shell -file ../build_portable.tcl -project_name build. The local_original project retains original absolute paths. Portable Tcl uses bundled sources; rerun timing qualification after any rebuild. No hardware burn or hardware acceptance was performed.\n')
receipt['source_project_zip']={'file':zip_path.name,'sha256':sha(zip_path),'bytes':zip_path.stat().st_size}
(E/'implementation.json').write_text(json.dumps(receipt,indent=2)+'\n')
(R/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print('PASS final PDS qualification and package:',json.dumps(receipt['artifacts']), 'zip:',receipt['source_project_zip'])
