"""Report native full-frame model results; never classify them as board results."""
import argparse,json,re
from pathlib import Path
def main():
 p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 cand=a.root/'diagnostics/ddr_camera_hires_prefetch_20261012/results'
 results=[]
 for mode,label in [(0,'serial'),(1,'eager_overlap'),(2,'late_overlap_source_prefetch')]:
  text=(cand/f'tb_fullhd_pipeline_{mode}.reproduction.log').read_text(encoding='utf-8-sig',errors='replace')
  config=re.search(r'FULLHD_PIPELINE_CONFIG overlap=(\d+) prefetch=(\d+) late_percent=(\d+)',text)
  passed=re.search(r'FULLHD_PIPELINE_PASS .*frames=(\d+) corrected_pixels=(\d+) display_pixels=(\d+) average_start_interval_cycles=(\d+) max_ui_wait=(\d+) overlap_beats=(\d+) native_reads=(\d+)',text)
  if not config or not passed or 'VERIFIED_PASS_BIT=1' not in text:raise RuntimeError(f'Missing verified result {mode}')
  expected=(int(mode>0),int(mode==2),95 if mode==2 else 0)
  if tuple(map(int,config.groups()))!=expected:raise RuntimeError('Configuration mismatch')
  ages=list(map(int,re.findall(r'FULLHD_FRAME_BEGIN .*source_age_ns=(\d+)',text)))
  pubages=list(map(int,re.findall(r'FULLHD_FRAME_PUBLISH .*image_age_ns=(\d+)',text)))
  phases=[]
  for values in re.findall(r'FULLHD_PHASE_PROFILE .*frame=(\d+) scan=(\d+) solve=(\d+) read=(\d+) interp=(\d+) write=(\d+) other=(\d+) processing_ns=(\d+)',text):
   frame,scan,solve,reads_phase,interp,write,other,ns=map(int,values)
   phases.append(dict(frame=frame,scan_cycles=scan,solve_cycles=solve,neighborhood_read_cycles=reads_phase,
    interpolation_cycles=interp,write_cycles=write,other_cycles=other,processing_ms=ns/1e6))
  frames,pixels,display,interval,wait,overlap,reads=map(int,passed.groups())
  if frames!=3 or pixels!=3*640*904 or display!=pixels or len(ages)!=3 or len(pubages)!=3 or len(phases)!=3:raise RuntimeError('Incomplete multi-frame validation')
  if mode==2 and max(ages)>50_000_000:raise RuntimeError('Freshness limit failed')
  results.append(dict(mode=label,average_start_interval_cycles=interval,average_start_interval_ms=interval/27000,
   corrected_pixels=pixels,display_pixels=display,source_age_ms=[v/1e6 for v in ages],image_age_at_publish_ms=[v/1e6 for v in pubages],
   max_ui_wait_cycles=wait,native_reads=reads,overlap_beats=overlap,phase_profiles=phases))
 base=results[0]['average_start_interval_cycles'];eager=results[1]['average_start_interval_cycles'];new=results[2]['average_start_interval_cycles']
 if new>=base:raise RuntimeError('Optimization acceptance failed: no native full-frame interval improvement')
 if max(results[2]['image_age_at_publish_ms'])>=max(results[0]['image_age_at_publish_ms']):
  raise RuntimeError('Optimization acceptance failed: maximum image age did not improve')
 record=dict(evidence='simulation_native_engine_full_algorithm_three_frames',hardware_accepted=False,
  source_size=[1920,1080],result_size=[640,904],display_size=[1920,1080],proc_clock_hz=27000000,
  reduction_vs_serial_percent=(base-new)*100/base,reduction_vs_eager_percent=(eager-new)*100/eager,results=results)
 a.output.write_text(json.dumps(record,indent=2)+'\n');print(json.dumps(record,indent=2))
if __name__=='__main__':main()
