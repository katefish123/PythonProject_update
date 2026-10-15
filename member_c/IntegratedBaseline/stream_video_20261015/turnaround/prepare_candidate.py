"""Remove retirement bubbles in a separately generated candidate; never programs hardware."""
from pathlib import Path
import argparse,hashlib,json,shutil
HERE=Path(__file__).resolve().parent
CAND=Path('diagnostics/ddr_camera_hires_prefetch_20261012/results')
def prepare(base,out):
 assert not out.exists()
 shutil.copytree(base,out,ignore=shutil.ignore_patterns('build_*'))
 build=out/CAND/'build.tcl';s=build.read_text().replace(base.as_posix(),out.as_posix())
 arb=out/'rtl/stream/ddr_arbiter3_turnaround.v';shutil.copyfile(HERE/arb.name,arb)
 s=s.replace('compile -top_module','add_design {'+arb.as_posix()+'}\ncompile -top_module');build.write_text(s)
 engine=out/'rtl/stream/ddr_word_engine_result_burst.v';shutil.copyfile(HERE/engine.name,engine)
 core=out/'rtl/top/video_correct_ddr_continuous_core.v';s=core.read_text().replace('ddr_arbiter3_fair ui_mux(', 'ddr_arbiter3_turnaround #(.BALANCE_C01(1)) ui_mux(');assert 'ddr_arbiter3_turnaround' in s;core.write_text(s)
 inner=out/'rtl/stream/c_stream_burst_correction_path.v';s=inner.read_text().replace('ddr_arbiter3 arbiter(', 'ddr_arbiter3_turnaround arbiter(');assert 'ddr_arbiter3_turnaround' in s;inner.write_text(s)
 mpath=out/'stream_sources.json';m=json.loads(mpath.read_text());m['candidate']='v4f_retire_accept'
 for p in [build,arb,engine,core,inner]:m['files'][p.relative_to(out).as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
 mpath.write_text(json.dumps(m,indent=2)+'\n')
 print('TURNAROUND_CANDIDATE_GENERATED; NOT timing/hardware qualified')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--baseline',required=True,type=Path);p.add_argument('--output',required=True,type=Path);a=p.parse_args();prepare(a.baseline.resolve(),a.output.resolve())
