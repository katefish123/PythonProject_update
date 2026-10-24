"""Exact full-chain fixture with the native-payload opt-in actually enabled."""
from pathlib import Path
import argparse,json,shutil
from prepare_writer_credit import sha
from prepare_native_payload import transform_core,transform_top,enable_bench

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--candidate',type=Path,required=True);p.add_argument('--previous',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    previous=a.previous.resolve();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
    shutil.copytree(previous/'source_snapshot',out/'source_snapshot')
    for n,fn in [('video_correct_ddr_continuous_core.v',transform_core),('video_correct_ddr_top.v',transform_top),('tb_lens_board.sv',enable_bench)]:
        f=out/'source_snapshot'/n
        if f.is_file():f.write_text(fn(f.read_text()))
    for f in (out/'source_snapshot').iterdir():
        if f.name!='tb_lens_board.sv' and sha(f)!=sha(a.candidate/'sources'/f.name):raise RuntimeError('Compiled production differs '+f.name)
    for n in ['run.ps1','source_binding.json','credit_binding.json','cache_binding.json']:
        if (previous/n).is_file():shutil.copyfile(previous/n,out/n)
    (out/'payload_binding.json').write_text(json.dumps({'previous':str(previous),
        'previous_bench_sha256':sha(previous/'source_snapshot/tb_lens_board.sv'),
        'enabled_bench_sha256':sha(out/'source_snapshot/tb_lens_board.sv'),
        'generator_sha256':sha(Path(__file__).with_name('prepare_native_payload.py')),
        'source_sha256':{p.name:sha(p) for p in (out/'source_snapshot').iterdir()},
        'bench_change':'Only BIST_ONLY_NATIVE_WDATA=1 at unique production core instance; no input/scoreboard/timing edits',
        'hardware_acceptance':False,'physical_timing_qualified':False},indent=2)+'\n')
    print(out)
