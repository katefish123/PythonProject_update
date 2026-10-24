"""Create a separate board for the cache decision timing cut, preserving clocks."""
from pathlib import Path
import argparse,json,shutil
from prepare_writer_credit import sha
from prepare_cache_decision import transform

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--baseline',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    base=a.baseline.resolve();out=a.output.resolve();m=json.loads((base/'source_manifest.json').read_text())
    if 'writer_credit' not in m or 'cache_decision' in m:raise RuntimeError('Expected ACK grant candidate')
    for n,h in m['candidate_source_sha256'].items():
        if sha(base/'sources'/n)!=h:raise RuntimeError('Parent source drift '+n)
    out.mkdir(parents=True,exist_ok=False);(out/'build').mkdir();shutil.copytree(base/'sources',out/'sources')
    n='ddr_quad_tile_cache.v';f=out/'sources'/n;f.write_text(transform(f.read_text()))
    expected=Path('D:/FPGA/output/cache_decision_20261023/generated')/n
    if sha(f)!=sha(expected):raise RuntimeError('Reviewed cache differs')
    m['changed'].append(n)
    m['cache_decision']={'parent':str(base),'parent_manifest_sha256':sha(base/'source_manifest.json'),
        'old_sha256':sha(base/'sources'/n),'new_sha256':sha(f),
        'generator_sha256':sha(Path(__file__).with_name('prepare_cache_decision.py')),
        'scope':'Register lookup-time protection/replacement/corner; choose victim and tag at existing fill_start; same interface/cycles/order'}
    m['candidate_source_sha256']={p.name:sha(p) for p in (out/'sources').iterdir()}
    (out/'source_manifest.json').write_text(json.dumps(m,indent=2)+'\n')
    (out/'build.tcl').write_text((base/'build.tcl').read_text().replace(base.as_posix(),out.as_posix()))
    print(out)
