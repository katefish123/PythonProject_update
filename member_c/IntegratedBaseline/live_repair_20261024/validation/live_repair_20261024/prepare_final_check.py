"""Freeze one routed DB and explicitly use it for independent STA and bitgen."""
from pathlib import Path
import argparse,hashlib,json,re,shutil
if not __debug__:raise RuntimeError('Refuse optimized Python')
p=argparse.ArgumentParser();p.add_argument('--repair',action='store_true');p.add_argument('--from-dir',default='performance');a=p.parse_args()
r=Path(__file__).resolve().parent;c=r/('candidate_repair' if a.repair else 'candidate_v2');upstream=c/a.from_dir
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
m=json.loads((c/'source_manifest.json').read_text())
for name,h in m['candidate_source_sha256'].items():assert sha(c/'sources'/name)==h
if a.from_dir!='build':
 prior=json.loads((upstream/'input_binding.json').read_text())
 assert prior['candidate_manifest_sha256']==sha(c/'source_manifest.json')
 assert prior['upstream_build_tcl_sha256']==sha(c/'build.tcl') and prior['route_tcl_sha256']==sha(upstream/'route.tcl')
 for name,v in prior['inputs'].items():assert sha(Path(name))==v['sha256']==sha(Path(v['upstream']))
text=(upstream/'pds_console.log' if a.from_dir!='build' else c/'pds_console.log').read_text(errors='replace')
assert 'Process "Generate Bitstream" done.' in text,'Implementation incomplete'
report=next((upstream/'report_timing').glob('*.rtr'))
assert 'Design Summary : All Constraints Met.' in report.read_text(errors='replace'),'Route still violates timing'
project=c/'build/build.pds';inputs=re.findall(r'_file "(\.\./sources/[^"]+)"',project.read_text(errors='replace'))
actual={(c/'build'/name).resolve().name:sha((c/'build'/name).resolve()) for name in inputs}
assert actual==m['candidate_source_sha256'],'Compiled project source list differs'
out=c/'final_check';out.mkdir(exist_ok=False);(out/'inputs').mkdir()
records={}
for f in [upstream/'place_route/video_correct_ddr_top_pnr.adf',c/'build/device_map/video_correct_ddr_top.pcf',project]:
 target=out/'inputs'/f.name;shutil.copyfile(f,target);records[str(target)]={'sha256':sha(target),'upstream':str(f)}
for name in ['input_binding.json','route.tcl','route.pds','pds_console.log'] if a.from_dir!='build' else []:
 f=upstream/name;target=out/'inputs'/('upstream_'+name);shutil.copyfile(f,target);records[str(target)]={'sha256':sha(target),'upstream':str(f)}
if a.from_dir=='build':
 f=c/'pds_console.log';target=out/'inputs/upstream_pds_console.log';shutil.copyfile(f,target);records[str(target)]={'sha256':sha(target),'upstream':str(f)}
f=c/'build.tcl';target=out/'inputs/upstream_build.tcl';shutil.copyfile(f,target);records[str(target)]={'sha256':sha(target),'upstream':str(f)}
db=out/'inputs/video_correct_ddr_top_pnr.adf';pcf=out/'inputs/video_correct_ddr_top.pcf'
script=(c/'build.tcl').read_text().split('compile -top_module')[0]
script+='add_constraint {'+pcf.as_posix()+'}\n'
script+='report_timing -force_to_run -input_db_file {'+db.as_posix()+'}\n'
script+='gen_bit_stream -force_to_run -input_db_file {'+db.as_posix()+'}\n'
# STA requires the completed PnR project context even with an explicit DB.
# Preserve its authentic task state rather than fabricate completion flags.
seed=upstream/('build.pds' if a.from_dir=='build' else 'route.pds')
template=out/'inputs/completed_upstream_project.pds';shutil.copyfile(seed,template)
records[str(template)]={'sha256':sha(template),'upstream':str(seed)}
shutil.copyfile(template,out/'route.pds')
(out/'route.tcl').write_text(script)
(out/'input_binding.json').write_text(json.dumps({'candidate_manifest_sha256':sha(c/'source_manifest.json'),'upstream_build_tcl_sha256':sha(c/'build.tcl'),'route_tcl_sha256':sha(out/'route.tcl'),'inputs':records,'upstream_implementation_log_sha256':sha(upstream/'pds_console.log' if a.from_dir!='build' else c/'pds_console.log'),'compiled_inputs':actual,'same_explicit_db_for_sta_and_bitgen':str(db)},indent=2)+'\n')
print(out)
