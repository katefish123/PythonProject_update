"""Bind continuous-system native DDR/HDMI evidence to the generated PDS inputs."""
from pathlib import Path
import argparse,hashlib,json,re,shutil
HERE=Path(__file__).resolve().parent
import sys
sys.path.insert(0,str(HERE.parent))
from verify_candidate import read_hashes
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def qualify(root,case_dirs,evidence):
 m=json.loads((root/'stream_sources.json').read_text())
 for name,h in m['files'].items():assert sha(root/name)==h,('manifest drift',name)
 for p in (root/'vendor/b').rglob('*'):
  if p.is_file():
   rel=p.relative_to(root/'vendor/b')
   original=HERE.parent.parent/('a_sync_20261013/accepted/vendor/b' if rel.parts[0]=='vectors' else 'a_black_sync_20261014/upstream/diagnostics/ddr_camera_black_20261014/b_algorithm')/rel
   assert p.read_bytes()==original.read_bytes(),p
 tests={};evidence.mkdir(parents=True,exist_ok=True)
 for folder in case_dirs:
  raw=(folder/'console.log').read_bytes();log=raw.decode('utf-16' if raw.startswith(b'\xff\xfe') else 'utf-8-sig')
  assert 'CONTINUOUS_SYSTEM_PASS' in log and 'VERIFIED_PASS_BIT=1' in log,folder
  assert 'Errors: 0, Warnings: 0' in log and not re.search(r'\*\* (?:Error|Warning|Fatal):',log),folder
  before=read_hashes(folder/'source_hashes.txt');after=read_hashes(folder/'source_hashes_after.txt');assert before==after
  for name,h in before.items():
   if name.endswith('.v') and 'output/' in name.replace('\\','/'):assert str(root).replace('\\','/').lower() in name.replace('\\','/').lower(),('mixed snapshot',name)
  p=re.search(r'CONTINUOUS_SYSTEM_PASS mode=(\d+) frames=(\d+) corrected_pixels=(\d+) display_pixels=(\d+)',log);assert p
  times=[int(x) for x in re.findall(r'CONTINUOUS_PUBLISH_INTERVAL[^\n]* ns=(\d+)',log)]
  phases=[int(x) for x in re.findall(r'processing_ns=(\d+)',log)]
  summary=re.search(r'CONTINUOUS_TELEMETRY[^\n]+',log);assert summary
  result={'native_fullhd':'STREAM_SYSTEM_CONFIG native=1' in log,'published_frames':int(p[2]),'corrected_pixels_checked':int(p[3]),'hdmi_pixels_checked':int(p[4]),'publication_intervals_ns':times,'processing_times_ns':phases,'mean_publication_ns':sum(times)/len(times),'telemetry':summary[0],'source_files':len(before),'log_sha256':sha(folder/'console.log')}
  if result['native_fullhd']:
   assert result['corrected_pixels_checked']==result['published_frames']*768*1080
   steady=times[1:] if len(times)>1 else times
   result['steady_new_images_per_second']=1e9/(sum(steady)/len(steady))
   result['all_steady_intervals_fit_60hz']=all(n<=16667000 for n in steady)
   scans=[tuple(map(int,x)) for x in re.findall(r'CONTINUOUS_HDMI_FRAME generation=\d+ displayed_id=(\d+) pixels=\d+ age_ms=\d+ unique_frames=(\d+) scan_frames=(\d+) time_ns=(\d+)',log)]
   unique=[]
   for scan in scans:
    if not unique or scan[1]!=unique[-1][1]:unique.append(scan)
   consecutive=[b[3]-a[3] for a,b in zip(unique,unique[1:]) if b[0]==a[0]+1]
   result['consecutive_good_hdmi_frame_intervals_ns']=consecutive
   result['steady_hdmi_new_images_per_second']=1e9/(sum(consecutive)/len(consecutive)) if consecutive else None
   result['all_consecutive_good_frames_displayed_next_scan']=bool(consecutive) and all(n<=16667000 for n in consecutive)
   telemetry={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',summary[0])}
   result['source_dropped_frames']=telemetry['dropped']
   result['native_simulation_60fps_verified']=result['published_frames']>=60 and len(consecutive)>=58 and result['all_consecutive_good_frames_displayed_next_scan'] and telemetry['dropped']==0

  target=evidence/folder.name;target.mkdir(exist_ok=True)
  for name in ['console.log','source_hashes.txt','source_hashes_after.txt','case.do']:shutil.copyfile(folder/name,target/name)
  tests[folder.name]=result
 build=root/'diagnostics/ddr_camera_hires_prefetch_20261012/results/build.tcl'
 inputs=re.findall(r'add_(?:design|constraint)[^\n]*\{([^}]+)\}',build.read_text())+[str(build),str(root/'stream_sources.json')]
 report={'candidate':m['candidate'],'status':'simulation_passed','source_size':[1920,1080],'effective_result_size':[765,1080],'stored_result_size':[768,1080],'hardware_accepted':False,'board_replacement_allowed':False,'full_corrected_camera_60fps_verified':False,'native_simulation_60fps_verified':any(t.get('native_simulation_60fps_verified',False) for t in tests.values()),'tests':tests,'implementation_inputs':{str(p):sha(p) for p in inputs},'limitations':['Native memory model includes arbitration/backpressure but cannot establish physical DDR timing.','No camera optical-sharpness acceptance.','Failed frames retain last complete image; age and reason counters expose holds.']}
 (evidence/'qualification.json').write_text(json.dumps(report,indent=2)+'\n')
 print('CONTINUOUS_SYSTEM_BINDING_PASS cases='+str(len(tests)))
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--root',required=True,type=Path);p.add_argument('--case',required=True,type=Path,action='append');p.add_argument('--evidence',required=True,type=Path);a=p.parse_args();qualify(a.root.resolve(),a.case,a.evidence.resolve())
