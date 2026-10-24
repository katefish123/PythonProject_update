"""Fresh full board with only a bound display lookahead delta."""
from pathlib import Path
import argparse,hashlib,json,shutil
from prepare_display_lookahead import transform

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--baseline',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    base=a.baseline.resolve();out=a.output.resolve();sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    q=json.loads((base/'release/qualification.json').read_text());assert q['timing_qualified']
    for n,h in q['candidate_source_sha256'].items():assert sha(base/'sources'/n)==h,n
    out.mkdir(parents=True,exist_ok=False);(out/'build').mkdir();shutil.copytree(base/'sources',out/'sources')
    name='ddr_result_display_raw_corrected.v';f=out/'sources'/name;f.write_text(transform((base/'sources'/name).read_text()))
    expected=Path('D:/FPGA/output/display_lookahead2_20261023')/name;assert sha(f)==sha(expected)
    m=json.loads((base/'source_manifest.json').read_text());m['changed']+=['ddr_result_display_raw_corrected.v']
    m['display_lookahead']={'qualified_parent':str(base),'parent_qualification_sha256':sha(base/'release/qualification.json'),
        'old_sha256':sha(base/'sources'/name),'new_sha256':sha(f),'generator_sha256':sha(Path(__file__).with_name('prepare_display_lookahead.py')),
        'scope':'Four physical row buffers and three-row lookahead; sensitivity regression improvement, not hardware acceptance'}
    m['candidate_source_sha256']={p.name:sha(p) for p in (out/'sources').iterdir()}
    (out/'source_manifest.json').write_text(json.dumps(m,indent=2)+'\n')
    (out/'build.tcl').write_text((base/'build.tcl').read_text().replace(base.as_posix(),out.as_posix()))
    print(out)
