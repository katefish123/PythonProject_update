"""Snapshot every PDS input into a standalone new project before implementation."""
from pathlib import Path
import json,hashlib,shutil,sys
H=Path(__file__).resolve().parent
out=Path(sys.argv[1]).resolve()
if out.exists():raise SystemExit('Use a new project directory')
(out/'sources').mkdir(parents=True)
(out/'build').mkdir()
m=json.loads((H/'source_manifest.json').read_text());mapping={}
for kind in ['designs','constraints']:
 for source,digest in m[kind].items():
  p=Path(source);target=out/'sources'/p.name
  assert not target.exists(),('duplicate filename',p)
  assert hashlib.sha256(p.read_bytes()).hexdigest()==digest,('source drift',p)
  shutil.copyfile(p,target);mapping[source]=target.as_posix()
script=(H/'build.tcl').read_text()
for old,new in mapping.items():script=script.replace(old,new)
(out/'build.tcl').write_text(script)
manifest={'hardware_accepted':False,'timing_qualified':False,'original_inputs':m,
 'frozen_inputs':{str(out/'sources'/Path(p).name):d for kind in ['designs','constraints'] for p,d in m[kind].items()}}
(out/'freeze_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Frozen project:',out,len(mapping),'inputs')
