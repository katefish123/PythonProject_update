"""Bind the continuous-system bench to a generated V3 board snapshot, read-only."""
from pathlib import Path
import argparse,json
HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser();p.add_argument('--baseline',type=Path,default=Path('D:/FPGA/output/c_stream_board_v3_20261015'));p.add_argument('--live',action='store_true');p.add_argument('--bench',type=Path,default=HERE/'tb_continuous_stream_system.sv');a=p.parse_args();base=a.baseline.resolve()
root=HERE.parent
required=[root/'continuous_integration/video_correct_ddr_continuous_core.v'] if a.live else [base/'rtl/top/video_correct_ddr_continuous_core.v']
required += [base/'vendor/b/rtl'/x for x in ['b_rectifier.v','bilinear_interp.v','homography_solver.v','perspective_coord.v','perspective_core.v','scaled_div_pipe.v','signed_div_seq.v','unsigned_div_seq.v']]
required += [base/'rtl/algo/c_corner_rectifier.v',base/'rtl/algo/marker_detector.v',base/'rtl/common/reset_sync.v',base/'rtl/memory/async_packet_fifo.v',base/'rtl/memory/ddr_arbiter3.v',base/'rtl/memory/ddr_self_test.v',base/'vendor/c_current/01_design_code/video_timing_vtc.v',base/'diagnostics/ddr_camera_hires_prefetch_20261012/results/ddr_result_display.v']
if a.live:
 for folder in ['processor','bridge','cache','capture_continuous']:
  required+=sorted((root/folder).glob('*.v'))
 required+=[root/'result_burst'/x for x in ['ddr_result_writer_burst64.v','ddr_word_engine_result_burst.v','c_stream_burst_correction_path.v']]
else:
 required += sorted((base/'rtl/stream').glob('*.v'))
# The generator may keep the new native engine at the diagnostic engine path.
text='\n'.join(x.read_text(encoding='utf-8',errors='ignore') for x in required if x.exists())
if 'module ddr_word_engine_result_burst' not in text:
 candidates=[x for x in base.rglob('*.v') if 'module ddr_word_engine_result_burst' in x.read_text(encoding='utf-8',errors='ignore')]
 assert len(candidates)==1,('expected one result-burst engine definition',candidates)
 required+=candidates
required += [a.bench.resolve()]
missing=[str(x) for x in required if not x.exists()]
assert not missing,('missing snapshot sources',missing)
modules={}
import re
for src in required:
 for mod in re.findall(r'^\s*module\s+(\w+)',src.read_text(encoding='utf-8',errors='ignore'),re.M):
  assert mod not in modules,('duplicate module',mod,modules.get(mod),src)
  modules[mod]=str(src)
for mod in ['video_correct_ddr_continuous_core','continuous_source_path','continuous_capture_rx','continuous_capture_manager','continuous_capture_geometry','continuous_capture_writer','c_stream_burst_correction_path','ddr_word_engine_result_burst','ddr_result_writer_burst64']:
 assert mod in modules,('missing module',mod)
(HERE/'sources.json').write_text(json.dumps([x.as_posix() for x in required],indent=2)+'\n')
print('CONTINUOUS_SYSTEM_BENCH_READY sources='+str(len(required)))

