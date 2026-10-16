"""Use an unused GPLL integer output for57.115MHz processing; preserve pixel/VCO."""
from pathlib import Path
import argparse,hashlib,json,shutil
HERE=Path(__file__).resolve().parent
CAND=Path('diagnostics/ddr_camera_hires_prefetch_20261012/results')
def prepare(base,out):
 assert not out.exists()
 shutil.copytree(base,out,ignore=shutil.ignore_patterns('build_*'))
 build=out/CAND/'build.tcl'
 script=build.read_text().replace(base.as_posix(),out.as_posix())
 assert script.count('\npnr\n')==1, 'Expected one implementation command'
 # Explicitly prioritize constrained slack in the router, including the
 # unchanged vendor UI-to-PHY command paths. No timing constraints are relaxed.
 script=script.replace('\npnr\n','\npnr -optimize_multi_corner_timing -slack_prior_in_global_router TRUE\n')
 build.write_text(script)
 pll=out/'vendor/c_current/01_design_code/ip/video_pll_27m_148m5/video_pll_27m_148m5.v';shutil.copyfile(HERE/pll.name,pll)
 top=out/CAND/'video_correct_ddr_top.v';s=top.read_text().replace('clkout54','clkout57').replace('proc_clk54','proc_clk57')
 s=s.replace('frame_telemetry_overlay telemetry_view(', 'frame_telemetry_overlay #(.PROC_CYCLES_PER_MS(57115)) telemetry_view(')
 s=s.replace('video_correct_ddr_continuous_core #(', 'video_correct_ddr_continuous_core #(.PROC_CYCLES_PER_MS(57115),')
 s=s.replace('CAPTURE_TIMEOUT(108000000)','CAPTURE_TIMEOUT(114230000)').replace('RETRY_CYCLES(540000)','RETRY_CYCLES(571150)');top.write_text(s)
 fdc=out/'constr/board_ddr.fdc';s=fdc.read_text().replace('processing_clock -period 18.518519','processing_clock -period 17.508418').replace('vp/u_gpll:CLKOUTF','vp/u_gpll:CLKOUT1');fdc.write_text(s)
 mp=out/'stream_sources.json';m=json.loads(mp.read_text());m['candidate']='v4k_processing57p115'
 for p in [build,pll,top,fdc]:m['files'][p.relative_to(out).as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
 m['processing_clock_mhz']=742.5/13;m['pixel_clock_mhz']=148.5;m['milliseconds_prescaler_cycles']=57115
 m['implementation_options']=['optimize_multi_corner_timing','slack_prior_in_global_router TRUE']
 mp.write_text(json.dumps(m,indent=2)+'\n');print('PROCESSING57_CANDIDATE_GENERATED; NOT timing/hardware qualified')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--baseline',required=True,type=Path);p.add_argument('--output',required=True,type=Path);a=p.parse_args();prepare(a.baseline.resolve(),a.output.resolve())
