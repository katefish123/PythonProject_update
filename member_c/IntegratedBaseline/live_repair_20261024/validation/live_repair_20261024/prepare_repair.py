"""Freeze tested writer delta on the diagnostic v2; no PDS/hardware action."""
from pathlib import Path
import hashlib,json,shutil
r=Path(__file__).resolve().parent;parent=r/'candidate_v2';out=r/'candidate_repair'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
writer=r/'writer_overlap/continuous_capture_writer.v'
expected='3c2a41136b9729a7a19df52158bfa5e942b0cf677a2bf0a1e035e04fd5f94ff0'
assert sha(writer)==expected,'Writer experiment drift'
out.mkdir(exist_ok=False);(out/'build').mkdir();shutil.copytree(parent/'sources',out/'sources')
shutil.copyfile(writer,out/'sources'/writer.name)
m=json.loads((parent/'source_manifest.json').read_text())
for name,h in m['candidate_source_sha256'].items():assert sha(parent/'sources'/name)==h,'Parent drift '+name
m['capture_overlap']={'parent':str(parent),'parent_manifest_sha256':sha(parent/'source_manifest.json'),'old_writer_sha256':sha(parent/'sources'/writer.name),'new_writer_sha256':expected,'scope':'Two owned assembly slots, one in-flight native write; unchanged FIFO and complete-frame contract','physical_qualified':False,'live_repair_accepted':False}
m['candidate_source_sha256']={p.name:sha(p) for p in (out/'sources').iterdir() if p.is_file()}
(out/'source_manifest.json').write_text(json.dumps(m,indent=2)+'\n')
(out/'build.tcl').write_text((parent/'build.tcl').read_text().replace(parent.as_posix(),out.as_posix()))
print('Repair source frozen; not built or authorized for programming')
