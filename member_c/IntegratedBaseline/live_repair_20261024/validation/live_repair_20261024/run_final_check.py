from pathlib import Path
import argparse,hashlib,json,subprocess,time,re
if not __debug__:raise RuntimeError('Refuse optimized Python')
ap=argparse.ArgumentParser();ap.add_argument('--repair',action='store_true');a=ap.parse_args()
r=Path(__file__).resolve().parent;c=r/('candidate_repair' if a.repair else 'candidate_v2');b=c/'final_check'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
binding=json.loads((b/'input_binding.json').read_text())
for name,v in binding['inputs'].items():assert sha(Path(name))==v['sha256']
argv=['D:/softwares/PDS/PDS_2022.2-SP6.4/bin/pds_shell.exe','-file',str(b/'route.tcl')]
before=sha(b/'route.tcl');start=time.time()
with (b/'pds_console.log').open('w') as f:p=subprocess.run(argv,cwd=b,stdout=f,stderr=subprocess.STDOUT)
assert p.returncode==0
# The shell wrapper can return success without starting STA. Use the already
# proven timing worker and require an actual fresh report from that worker.
project=b/'route.pds';project_text=project.read_text(errors='replace')
section=project_text.split('(_command cmd_report_post_pnr_timing',1)[1].split('(_widget',1)[0]
selected=re.search(r'\(_option input_db_file\s+\(_file "([^"]+)"',section).group(1)
assert (b/selected).resolve()==Path(binding['same_explicit_db_for_sta_and_bitgen']).resolve()
worker_argv=['D:/softwares/PDS/PDS_2022.2-SP6.4/bin/pds_shell.exe','-action','report_timing','-project_file',str(project)]
project_before=sha(project)
with (b/'report_direct.log').open('w') as f:worker=subprocess.run(worker_argv,cwd=b,stdout=f,stderr=subprocess.STDOUT)
assert worker.returncode==0 and 'Report timing is finished successfully.' in (b/'report_direct.log').read_text(errors='replace')
assert (b/'video_correct_ddr_top.rtr').stat().st_size>1000
for name,v in binding['inputs'].items():assert sha(Path(name))==v['sha256']
assert sha(b/'route.tcl')==before
(b/'execution.json').write_text(json.dumps({'argv':argv,'cwd':str(b),'exit_code':p.returncode,'elapsed_seconds':time.time()-start,'script_sha256':before,'input_binding_sha256':sha(b/'input_binding.json'),'log_sha256':sha(b/'pds_console.log'),'timing_worker_argv':worker_argv,'timing_worker_exit_code':worker.returncode,'timing_worker_log_sha256':sha(b/'report_direct.log'),'timing_project_before_sha256':project_before,'timing_project_after_sha256':sha(project),'timing_input_db_sha256':sha(Path(binding['same_explicit_db_for_sta_and_bitgen']))},indent=2)+'\n')
if p.returncode:raise RuntimeError('Independent physical check failed')
print('Independent same-DB STA+bitgen finished; run qualification gate')
