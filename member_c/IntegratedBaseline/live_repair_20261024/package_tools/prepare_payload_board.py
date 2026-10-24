"""Enable the reviewed native-BIST payload contract in a fresh production board."""
from pathlib import Path
import argparse,json,shutil
from prepare_writer_credit import sha
from prepare_native_payload import transform_core,transform_top

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--baseline',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    base=a.baseline.resolve();out=a.output.resolve();m=json.loads((base/'source_manifest.json').read_text())
    if 'cache_decision' not in m or 'native_payload' in m:raise RuntimeError('Expected reviewed cache candidate')
    for n,h in m['candidate_source_sha256'].items():
        if sha(base/'sources'/n)!=h:raise RuntimeError('Parent drift '+n)
    out.mkdir(parents=True,exist_ok=False);(out/'build').mkdir();shutil.copytree(base/'sources',out/'sources')
    changes={}
    for n,fn in [('video_correct_ddr_continuous_core.v',transform_core),('video_correct_ddr_top.v',transform_top)]:
        f=out/'sources'/n;old=sha(f);f.write_text(fn(f.read_text()))
        if sha(f)!=sha(Path('D:/FPGA/output/native_payload_20261023/generated')/n):raise RuntimeError('Reviewed source differs '+n)
        changes[n]={'old_sha256':old,'new_sha256':sha(f)}
    m['changed'].append('video_correct_ddr_continuous_core.v')
    m['native_payload']={'parent':str(base),'parent_manifest_sha256':sha(base/'source_manifest.json'),
        'files':changes,'generator_sha256':sha(Path(__file__).with_name('prepare_native_payload.py')),
        'scope':'Default-off BIST-only single-beat WDATA; production core/engine capture8; video burst buses, latency and ownership unchanged'}
    m['candidate_source_sha256']={p.name:sha(p) for p in (out/'sources').iterdir()}
    (out/'source_manifest.json').write_text(json.dumps(m,indent=2)+'\n')
    (out/'build.tcl').write_text((base/'build.tcl').read_text().replace(base.as_posix(),out.as_posix()))
    print(out)
