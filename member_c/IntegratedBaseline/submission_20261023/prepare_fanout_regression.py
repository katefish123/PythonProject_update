"""Preserve a tested payload fixture, changing only the annotated cache file."""
from pathlib import Path
import argparse,json,shutil
from prepare_writer_credit import sha
from prepare_lookup_fanout import transform

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--candidate',type=Path,required=True);p.add_argument('--previous',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    previous=a.previous.resolve();out=a.output.resolve();src=previous/'source_snapshot';name='ddr_quad_tile_cache.v'
    expected=transform((src/name).read_text(encoding='utf-8'))
    if expected!=(a.candidate/'sources'/name).read_text(encoding='utf-8'):raise RuntimeError('Fanout transform differs')
    out.mkdir(parents=True,exist_ok=False);shutil.copytree(src,out/'source_snapshot')
    (out/'source_snapshot'/name).write_text(expected,encoding='utf-8')
    for f in (out/'source_snapshot').iterdir():
        if f.name!='tb_lens_board.sv' and sha(f)!=sha(a.candidate/'sources'/f.name):raise RuntimeError('Production source differs '+f.name)
    for n in ['run.ps1','source_binding.json','credit_binding.json','cache_binding.json','payload_binding.json']:
        if (previous/n).is_file():shutil.copyfile(previous/n,out/n)
    (out/'fanout_binding.json').write_text(json.dumps({'previous':str(previous),'previous_bench_sha256':sha(src/'tb_lens_board.sv'),'bench_sha256':sha(out/'source_snapshot/tb_lens_board.sv'),'old_cache_sha256':sha(src/name),'new_cache_sha256':sha(out/'source_snapshot'/name),'generator_sha256':sha(Path(__file__).with_name('prepare_lookup_fanout.py')),'scope':'Identical stimulus, timing and scoreboards; only four synthesis fanout attributes'},indent=2)+'\n',encoding='utf-8')
    print(out)
