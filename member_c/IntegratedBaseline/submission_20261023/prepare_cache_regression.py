"""Same complete-chain stimulus and sources, changing only cache decision tails."""
from pathlib import Path
import argparse,json,shutil
from prepare_writer_credit import sha
from prepare_cache_decision import transform

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--previous',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    previous=a.previous.resolve();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
    shutil.copytree(previous/'source_snapshot',out/'source_snapshot')
    n='ddr_quad_tile_cache.v';f=out/'source_snapshot'/n;f.write_text(transform(f.read_text()))
    for p in (previous/'source_snapshot').iterdir():
        if p.name!=n and sha(p)!=sha(out/'source_snapshot'/p.name):raise RuntimeError('Unexpected change '+p.name)
    for n in ['run.ps1','source_binding.json','credit_binding.json']:
        if (previous/n).is_file():shutil.copyfile(previous/n,out/n)
    (out/'cache_binding.json').write_text(json.dumps({'previous':str(previous),
        'previous_bench_sha256':sha(previous/'source_snapshot/tb_lens_board.sv'),
        'cache_old_sha256':sha(previous/'source_snapshot/ddr_quad_tile_cache.v'),
        'cache_new_sha256':sha(f),'transform_sha256':sha(Path(__file__).with_name('prepare_cache_decision.py')),
        'source_sha256':{p.name:sha(p) for p in (out/'source_snapshot').iterdir()},
        'hardware_acceptance':False,'physical_timing_qualified':False},indent=2)+'\n')
    print(out)
