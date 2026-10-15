"""Create separately bound display-block experiment from immutable V3 snapshot."""
from pathlib import Path
import argparse,hashlib,json,shutil
HERE=Path(__file__).resolve().parent
CAND=Path('diagnostics/ddr_camera_hires_prefetch_20261012/results')
def prepare(base,out,fair=False):
 assert base!=out and not out.exists()
 shutil.copytree(base,out)
 build=out/CAND/'build.tcl';build.write_text(build.read_text().replace(base.as_posix(),out.as_posix()))
 core=out/'rtl/top/video_correct_ddr_continuous_core.v';s=core.read_text()
 assert s.count('ddr_result_display #(')==1
 s=s.replace('ddr_result_display #(','ddr_result_display_block64 #(').replace('.rsp_valid(display_rsp),.rsp_rdata(display_rdata),','.rsp_valid(display_rsp),.rsp_rdata(display_rdata),.rsp_block(rsp_source_block),')
 core.write_text(s)
 changed=[core,build]
 if fair:
  q=out/'rtl/stream/ddr_arbiter3_fair.v';shutil.copyfile(HERE.parent/'arbitration/ddr_arbiter3_fair.v',q);changed.append(q)
  s=core.read_text().replace('ddr_arbiter3 ui_mux(', 'ddr_arbiter3_fair ui_mux(')
  s=s.replace('selftest_passed&&app_v&&!display_v&&!cap_v&&br_source_block','selftest_passed&&br_r&&br_source_block')
  s=s.replace('selftest_passed&&app_v&&!display_v&&!cap_v&&br_result_block','selftest_passed&&br_r&&br_result_block')
  core.write_text(s)
  build.write_text(build.read_text().replace('compile -top_module','add_design {'+q.as_posix()+'}\ncompile -top_module'))
 cache=out/'rtl/stream/ddr_quad_tile_cache.v'
 shutil.copyfile(HERE.parent/'cache/ddr_quad_tile_cache.v',cache);changed.append(cache)
 for name in ['ddr_word_engine_result_burst.v','ddr_result_display_block64.v']:
  dst=out/'rtl/stream'/name;shutil.copyfile(HERE/name,dst);changed.append(dst)
 build.write_text(build.read_text().replace('compile -top_module','add_design {'+(out/'rtl/stream/ddr_result_display_block64.v').as_posix()+'}\ncompile -top_module'))
 mpath=out/'stream_sources.json';m=json.loads(mpath.read_text())
 for p in changed:m['files'][p.relative_to(out).as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
 m['candidate']='v4d_fair_display_block' if fair else 'v4c_display_block_registered_victim';m['hardware_accepted']=False;m['board_replacement_allowed']=False
 mpath.write_text(json.dumps(m,indent=2)+'\n')
 print('DISPLAY_BLOCK_CANDIDATE_GENERATED; NOT timing/hardware qualified')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--baseline',required=True,type=Path);p.add_argument('--output',required=True,type=Path);p.add_argument('--fair',action='store_true');a=p.parse_args();prepare(a.baseline.resolve(),a.output.resolve(),a.fair)
