"""Read-only source/log binding verification for the V4N DRM path repair."""
from pathlib import Path
import json,hashlib,re
HERE=Path(__file__).resolve().parent
ROOT=HERE.parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def recorded(path):
 data={}
 for b in re.split(r'\r?\n\s*\r?\n',path.read_text(encoding='utf-8-sig')):
  h=re.search(r'Hash\s*:\s*([a-fA-F0-9]{64})',b);p=re.search(r'Path\s*:\s*(.*)',b,re.S)
  if h and p:data[Path(''.join(x.strip() for x in p[1].splitlines())).name]=h[1].lower()
 assert data
 return data
s=json.loads((HERE/'repair_summary_v4n.json').read_text())
for test in s['tests']:
 d=ROOT/test['module']/'evidence/drm_prefetch_v4n';m=json.loads((d/'manifest.json').read_text())
 assert sha(d/'manifest.json')==test['manifest_sha256']
 for name,digest in m['files_sha256'].items():assert sha(d/name)==digest,'archive changed: '+name
 for name,digest in m['current_source_sha256'].items():assert sha(ROOT/test['module']/name)==digest,'current source changed: '+name
 log=(d/'simulation.log').read_text(encoding='utf-8-sig');compile_log=(d/'compile.log').read_text(encoding='utf-8-sig')
 for text in [log,compile_log]:
  assert 'Errors: 0, Warnings: 0' in text
  assert not re.search(r'\*\* (?:Fatal|Error|Warning):',text)
 assert test['result'] in log
 assert m['old_structure_expected_failure'] in (d/'structure_v4n_red.log').read_text()
 names=['source_hashes_before.txt','source_hashes_after.txt'] if test['module']=='status_timing' else ['source_hashes.txt']
 hashes=[recorded(d/n) for n in names]
 assert all(v==hashes[0] for v in hashes)
 for name,digest in hashes[0].items():assert sha(d/'sources'/name)==digest,'runtime hash mismatch: '+name
 assert 'PASS ' in (d/'structure_green_current.log').read_text()
print('PASS V4N DRM evidence: frozen RTL/benches/runners and runtime hashes match; both raster tests 0 errors/warnings; both original path structures rejected')
