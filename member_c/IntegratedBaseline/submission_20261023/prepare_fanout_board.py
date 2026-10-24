"""Create a new immutable fanout-only child, never modify its running parent."""
from pathlib import Path
import argparse,json,shutil
from prepare_writer_credit import sha
from prepare_lookup_fanout import transform,restore

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--baseline',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    base=a.baseline.resolve();out=a.output.resolve();m=json.loads((base/'source_manifest.json').read_text(encoding='utf-8'))
    if 'native_payload' not in m or 'lookup_fanout' in m:raise RuntimeError('Expected frozen payload parent')
    for n,h in m['candidate_source_sha256'].items():
        if sha(base/'sources'/n)!=h:raise RuntimeError('Parent drift '+n)
    name='ddr_quad_tile_cache.v';before=(base/'sources'/name).read_text(encoding='utf-8');after=transform(before)
    if restore(after)!=before:raise RuntimeError('Unexpected logical change')
    out.mkdir(parents=True,exist_ok=False);(out/'build').mkdir();shutil.copytree(base/'sources',out/'sources')
    target=out/'sources'/name;target.write_text(after,encoding='utf-8')
    micro=Path('D:/FPGA/output/lookup_fanout_micro_20261023');v=json.loads((micro/'verification.json').read_text(encoding='utf-8'))
    if v['generated_sha256']!=sha(target) or v['source_sha256']!=sha(base/'sources'/name):raise RuntimeError('Reviewed micro source differs')
    m['lookup_fanout']={'parent':str(base),'parent_manifest_sha256':sha(base/'source_manifest.json'),'old_sha256':sha(base/'sources'/name),'new_sha256':sha(target),'generator_sha256':sha(Path(__file__).with_name('prepare_lookup_fanout.py')),'micro_directory':str(micro),'verification_sha256':sha(micro/'verification.json'),'scope':'Only four lookup coordinates syn_maxfan=32; no expressions, registers, cycles or reset changes; physical effects unqualified'}
    m['candidate_source_sha256']={f.name:sha(f) for f in (out/'sources').iterdir()}
    (out/'source_manifest.json').write_text(json.dumps(m,indent=2)+'\n',encoding='utf-8')
    (out/'build.tcl').write_text((base/'build.tcl').read_text(encoding='utf-8').replace(base.as_posix(),out.as_posix()),encoding='utf-8')
    print(out)
