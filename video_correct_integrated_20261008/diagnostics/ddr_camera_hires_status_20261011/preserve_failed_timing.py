"""Retain the rejected placement and its exact sources before the RAM-style repair."""
from datetime import datetime,timezone
from pathlib import Path
import hashlib
import json
import shutil
import zipfile

D=Path(__file__).resolve().parent
R=D.parents[1]
O=D/"results"
F=D/"rejected_timing_20261011_213633"
F.mkdir(exist_ok=False)
for p in [O/"report_timing/video_correct_ddr_top.rtr",O/"build_run.log",O/"source_hashes.json",
          O/"simulation_qualification.json",O/"ddr_camera_hires_status.pds",O/"build.tcl"]:
    shutil.copyfile(p,F/p.name)
manifest=json.loads((O/"source_hashes.json").read_text(encoding="utf-8-sig"))
for name in ["sbit","smsk"]:
    p=O/("generate_bitstream/video_correct_ddr_top."+name)
    shutil.copyfile(p,F/p.name)
with zipfile.ZipFile(F/"source_snapshot_rejected.zip","x",zipfile.ZIP_DEFLATED) as z:
    for p in dict.fromkeys([Path(p) for p in manifest]+list(D.glob("*.py"))+list(D.glob("*.ps1"))+list(D.glob("*.v"))):
        z.write(p,p.relative_to(R).as_posix())
record={"recorded_at_utc":datetime.now(timezone.utc).isoformat(),"programmed":False,"rejected":True,
    "reason":"One fast-corner hold violation -0.001ns from display beat_data[144] to inferred distributed line RAM data input; no timing exception added.",
    "repair":"Use the documented Pango syn_ramstyle=block_ram attribute for packed line buffers; retain constraints and rerun qualification.",
    "files":{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in F.iterdir() if p.is_file()}}
(F/"rejection.json").write_text(json.dumps(record,indent=2)+"\n",encoding="utf-8")
print("Retained rejected timing/source/bitstream; it was not programmed.")
