"""SHA-bound derivation, keeping the validated numeric baseline unchanged."""
from pathlib import Path
import hashlib,json
H=Path(__file__).resolve().parent;B=H.parent/'lens_model_next';O=H/'generated';O.mkdir(exist_ok=True)
m=json.loads((B/'verification.json').read_text());sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
sources={}
for name in ('lens_map.v','lens_composed_map.v'):
 p=B/name;assert sha(p)==m['source_sha256'][name],('baseline drift',name)
 text=p.read_text()
 for old,new in [('module lens_composed_map(','module lens_composed_map_fast('),('module lens_map(','module lens_map_fast('),('q30_alu arithmetic(','q30_alu_fast arithmetic('),('lens_map lens(','lens_map_fast lens(')]:
  if old in text:text=text.replace(old,new)
 out=O/(p.stem+'_fast.v');out.write_text(text)
 sources[name]={'baseline_sha256':sha(p),'derived_sha256':sha(out)}
(O/'source_manifest.json').write_text(json.dumps(sources,indent=2)+'\n')
print('Prepared exact derived fast wrappers; original baseline unchanged')
