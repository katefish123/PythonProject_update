"""Reproducibly generate continuous-capture/burst-write candidate; never program hardware."""
from pathlib import Path
import argparse, hashlib, json, shutil, subprocess, sys
HERE=Path(__file__).resolve().parent
ROOT=HERE.parent
CAND=Path('diagnostics/ddr_camera_hires_prefetch_20261012/results')
def once(s,old,new):
 assert s.count(old)==1,(old,s.count(old))
 return s.replace(old,new,1)
def prepare(out):
 subprocess.run([sys.executable,str(ROOT/'prepare_board.py'),'--output',str(out)],check=True)
 sources=[]
 for folder in ('capture_continuous','result_burst'):
  for src in sorted((ROOT/folder).glob('*.v')):
   dst=out/'rtl/stream'/src.name
   shutil.copyfile(src,dst);sources.append(dst)
 core=out/'rtl/top/video_correct_ddr_continuous_core.v'
 shutil.copyfile(HERE/core.name,core);sources.append(core)
 top=out/CAND/'video_correct_ddr_top.v'
 s=top.read_text()
 s=once(s,'video_correct_ddr_stream_core #(','video_correct_ddr_continuous_core #(')
 s=once(s,'engine_fault,source_block;','engine_fault,source_block,result_block;wire[2047:0]full_result_block;')
 s=once(s,'.cmd_source_block(source_block),.rsp_source_block(full_source_block),.cmd_burst_data(capture_burst_data),','.cmd_result_block(result_block),.result_block_data(full_result_block),.cmd_source_block(source_block),.rsp_source_block(full_source_block),.cmd_burst_data(capture_burst_data),')
 s=once(s,'ddr_word_engine #(','ddr_word_engine_result_burst #(')
 s=once(s,'engine(.cmd_source_block(source_block),','engine(.cmd_result_block(result_block),.result_block_data(full_result_block),.cmd_source_block(source_block),')
 top.write_text(s)
 build=out/CAND/'build.tcl'
 s=once(build.read_text(),'compile -top_module',''.join('add_design {'+p.as_posix()+'}\n' for p in sources)+'compile -top_module')
 build.write_text(s)
 manifest=json.loads((out/'stream_sources.json').read_text())
 for p in [*sources,top,build]: manifest['files'][p.relative_to(out).as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
 manifest.update(candidate='v3_continuous_capture_result_burst',hardware_accepted=False,board_replacement_allowed=False,reset_contract='All domain resets and engine share asynchronous hard assertion; locally synchronized release.')
 (out/'stream_sources.json').write_text(json.dumps(manifest,indent=2)+'\n')
 from install_telemetry import install
 install(out)
 print('CONTINUOUS_BOARD_CANDIDATE_GENERATED; NOT hardware qualified')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args();prepare(a.output.resolve())
