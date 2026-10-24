from pathlib import Path
import hashlib,json
r=Path(__file__).resolve().parent;c=r/'candidate_v2';base=Path('D:/FPGA/output/b_lens_board_payload_20261023')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
from diagnostic_transform import transform
p=c/'sources/video_correct_ddr_top.v';t=transform(p.read_text())
p.write_text(t)
m=json.loads((base/'source_manifest.json').read_text());m['live_diagnostics']={'parent':str(base),'scope':'Observation only; always visible; reject histogram and service/scan counters','parent_top_sha256':sha(base/'sources/video_correct_ddr_top.v')}
m['candidate_source_sha256']={f.name:sha(f) for f in (c/'sources').iterdir() if f.is_file()}
(c/'source_manifest.json').write_text(json.dumps(m,indent=2)+'\n')
(c/'build').mkdir(exist_ok=True)
(c/'build.tcl').write_text((base/'build.tcl').read_text().replace(base.as_posix(),c.as_posix()))
print('Diagnostic source prepared; not physically qualified or released')
