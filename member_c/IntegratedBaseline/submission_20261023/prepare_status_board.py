"""Prepare fresh status-only candidate from exact qualified presentation image."""
from pathlib import Path
import argparse,hashlib,json,shutil
from repair_status_rom import repair

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--baseline',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();base=a.baseline.resolve();out=a.output.resolve()
    q=json.loads((base/'release/qualification.json').read_text())
    assert q['timing_qualified']
    for n,h in q['candidate_source_sha256'].items():assert sha(base/'sources'/n)==h,n
    out.mkdir(parents=True,exist_ok=False);(out/'build').mkdir();shutil.copytree(base/'sources',out/'sources')
    rtl=out/'sources/status_overlay.v';rtl.write_text(repair(rtl.read_text()))
    m=json.loads((base/'source_manifest.json').read_text())
    m['changed']=m['changed']+['status_overlay.v']
    m['status_rom_repair']={'parent':str(base),'parent_qualification_sha256':sha(base/'release/qualification.json'),
        'old_sha256':sha(base/'sources/status_overlay.v'),'new_sha256':sha(rtl),
        'green_test':'D:/FPGA/output/status_rom_green_20261023','red_test':'D:/FPGA/output/status_rom_red_20261023',
        'scope':'Remove duplicate case addresses, retain intended last glyph for each address; pixel fault unresolved'}
    m['candidate_source_sha256']={p.name:sha(p) for p in (out/'sources').iterdir()}
    (out/'source_manifest.json').write_text(json.dumps(m,indent=2)+'\n')
    (out/'build.tcl').write_text((base/'build.tcl').read_text().replace(base.as_posix(),out.as_posix()))
    print(out)
