"""Apply tested miss-only cache fill scheduling to immutable turnaround snapshot."""
from pathlib import Path
import argparse,hashlib,json,shutil
HERE=Path(__file__).resolve().parent
CAND=Path('diagnostics/ddr_camera_hires_prefetch_20261012/results')
def prepare(base,out):
 assert not out.exists()
 shutil.copytree(base,out,ignore=shutil.ignore_patterns('build_*'))
 build=out/CAND/'build.tcl';build.write_text(build.read_text().replace(base.as_posix(),out.as_posix()))
 cache=out/'rtl/stream/ddr_quad_tile_cache.v';shutil.copyfile(HERE/cache.name,cache)
 display=out/'rtl/stream/ddr_result_display_block64.v';shutil.copyfile(HERE/display.name,display)
 mp=out/'stream_sources.json';m=json.loads(mp.read_text());m['candidate']='v4j_cache_fill_scheduled_display'
 for p in [build,cache,display]:m['files'][p.relative_to(out).as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
 mp.write_text(json.dumps(m,indent=2)+'\n');print('CACHE_FILL_CANDIDATE_GENERATED; NOT timing/hardware qualified')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--baseline',required=True,type=Path);p.add_argument('--output',required=True,type=Path);a=p.parse_args();prepare(a.baseline.resolve(),a.output.resolve())
