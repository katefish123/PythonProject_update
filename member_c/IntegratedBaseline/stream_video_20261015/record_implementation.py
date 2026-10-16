"""Record physical implementation status without granting board acceptance."""
from pathlib import Path
import argparse,hashlib,json,re,shutil
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def record(root,build,out,exit_code):
 m=json.loads((root/'stream_sources.json').read_text())
 for name,h in m['files'].items():assert sha(root/name)==h,('implementation input drift',name)
 build_script=root/'diagnostics/ddr_camera_hires_prefetch_20261012/results/build.tcl'
 input_paths=[Path(x) for x in re.findall(r'add_(?:design|constraint)[^\n]*\{([^}]+)\}',build_script.read_text())]
 input_hashes={str(p.relative_to(root)):sha(p) for p in input_paths}
 previous=out/'implementation_status.json'
 if previous.exists():
  old=json.loads(previous.read_text())
  if old.get('root')==str(root) and 'implementation_inputs' in old:
   assert old['implementation_inputs']==input_hashes,'physical implementation inputs changed during build'
 report=build/'report_timing/video_correct_ddr_top.rtr'
 if not report.exists():report=build/'place_route/video_correct_ddr_top_timing_summary_after_hold_fix.txt'
 log=build/'build.log';raw=log.read_bytes();text=raw.decode('utf-16' if raw.startswith(b'\xff\xfe') else 'utf-8-sig',errors='replace')
 status='running' if exit_code is None else 'implementation_failed'
 summary=report.read_text() if report.exists() else None
 finished=exit_code==0 and 'Executing : gen_bit_stream successfully.' in text and bool(summary)
 timing_passed=bool(finished and 'Design Summary : All Constraints Met.' in summary)
 if finished:status='timing_passed' if timing_passed else 'timing_failed'
 clocks={}
 if summary:
  slow=summary.split('Setup Summary(Slow Corner):',1)[-1].split('Hold Summary',1)[0]
  for a,b,w,t,n,total in re.findall(r'^\s*(\S+)\s+(\S+)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*$',slow,re.M):
   if a==b:clocks[a]={'setup_wns_ns':float(w),'failing_endpoints':int(n),'total_endpoints':int(total)}
 result={'candidate':m['candidate'],'status':status,'process_exit_code':exit_code,'timing_passed':timing_passed,'hardware_accepted':False,'board_replacement_allowed':False,'root':str(root),'build':str(build),'slow_corner_same_clock_setup':clocks,'source_manifest_sha256':sha(root/'stream_sources.json'),'build_log_sha256':sha(log),'timing_report_sha256':sha(report) if summary else None,'implementation_inputs':input_hashes,'limitations':['Physical timing is evaluated against the recorded constraints; asynchronous CDC review and actual camera/board tests remain separate.']}
 out.mkdir(parents=True,exist_ok=True)
 if summary:shutil.copyfile(report,out/('final_timing.rtr' if report.suffix=='.rtr' else 'timing_summary_after_hold_fix.txt'))
 (out/'implementation_status.json').write_text(json.dumps(result,indent=2)+'\n')
 print('IMPLEMENTATION_STATUS '+status)
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--root',required=True,type=Path);p.add_argument('--build',required=True,type=Path);p.add_argument('--evidence',required=True,type=Path);p.add_argument('--exit-code',type=int);a=p.parse_args();record(a.root.resolve(),a.build.resolve(),a.evidence.resolve(),a.exit_code)
