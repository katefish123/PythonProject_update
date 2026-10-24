"""Materialize intended replacement glyphs once per address in a fresh file."""
from pathlib import Path
import argparse,hashlib,json,re

ROW=re.compile(r"^9'h([0-9a-f]+): bits=160'h([0-9a-f]+);$",re.M)

def repair(text):
    matches=list(ROW.finditer(text));last={m[1]:m.start() for m in matches}
    return ROW.sub(lambda m:m[0] if last[m[1]]==m.start() else '',text)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();assert not a.output.exists(),'Preserve existing candidate'
    original=a.source.read_text();fixed=repair(original)
    a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(fixed)
    before=ROW.findall(original);after=ROW.findall(fixed)
    assert len(after)==len(dict(before)) and dict(after)==dict(before)
    manifest={'scope':'Status ROM replacement precedence only; no capture/DDR/B datapath fix',
        'source':str(a.source),'original_sha256':hashlib.sha256(a.source.read_bytes()).hexdigest(),
        'output':str(a.output),'output_sha256':hashlib.sha256(a.output.read_bytes()).hexdigest(),
        'removed_duplicate_rows':len(before)-len(after),'hardware_programmed':False}
    a.output.with_suffix('.binding.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps(manifest,indent=2))
