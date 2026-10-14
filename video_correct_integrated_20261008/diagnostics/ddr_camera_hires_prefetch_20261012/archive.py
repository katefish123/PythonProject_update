"""Seal the existing prefetch build only if its complete saved checks still match."""
from datetime import datetime,timezone
from pathlib import Path
import hashlib
import json
import re
import shutil
import zipfile

D=Path(__file__).resolve().parent
R=D.parents[1]
O=D/"results"
release=R/"release/ddr_camera_hires_prefetch_20261012"
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):
    raw=p.read_bytes()
    return raw.decode("utf-16") if raw.startswith((b"\xff\xfe",b"\xfe\xff")) else raw.decode("utf-8-sig",errors="replace")
tests=json.loads(read(O/"simulation_qualification.json"))
assert len(tests["tests"])==12 and all(t["passed"] for t in tests["tests"].values())
for t in tests["tests"].values():
    p=Path(t["log"])
    assert sha(p)==t["log_sha256"]
    log=read(p)
    assert t["pass_message"] in log and "VERIFIED_PASS_BIT=1" in log
    assert not re.search(r"\*\* (Warning|Error|Fatal)|FAIL_",log)
timing=O/"report_timing/video_correct_ddr_top.rtr"
assert "Design Summary : All Constraints Met." in read(timing)
assert "Executing : gen_bit_stream successfully." in read(O/"build_run.log")
sources=json.loads(read(O/"source_hashes.json"))
base=R/"release/ddr_camera_hires_20261011"
baseline=json.loads(read(base/"source_hashes.json"))
for p,digest in baseline.items():assert sha(Path(p))==digest,p
changed_names={"video_correct_ddr_top.v","ddr_result_display.v","ddr_word_engine.v"}
changed=[];unchanged=[]
for name,digest in sources.items():
    p=Path(name);assert sha(p)==digest,name
    if p.name in changed_names:
        assert p.parent==O
        originals=[Path(q) for q in baseline if Path(q).name==p.name]
        assert len(originals)==1 and sha(originals[0])!=digest
        changed.append(p.name)
    else:
        assert baseline.get(name)==digest,name
        unchanged.append(name)
assert set(changed)==changed_names
bit=O/"generate_bitstream/video_correct_ddr_top.sbit"
mask=bit.with_suffix(".smsk")
assert bit.stat().st_size==mask.stat().st_size==3791112
assert sha(bit)=="60fb0b53a5c13b2c1adf47539c66bb4426d967effa2e3f2a279a9cac09865f22"
assert sha(mask)=="161f64918b0459b24282a733030b142ee14976a65035d8d6d989955bbe2585da"
release.mkdir(exist_ok=False)
for p in [bit,mask,timing,O/"source_hashes.json",O/"build_run.log",O/"simulation_qualification.json",O/"configuration.json",O/"fixture.json"]+[Path(t["log"]) for t in tests["tests"].values()]:
    shutil.copyfile(p,release/p.name)
files=[Path(p) for p in sources]+list(D.glob("*.py"))+list(D.glob("*.ps1"))+list(D.glob("*.sv"))
files+=[O/"build.tcl",O/"simulation_cases.json",O/"ddr_camera_hires_prefetch.pds"]
files+=list(O.glob("tb*.sv"))+list(O.glob("tb*.do"))+list(O.glob("*.hex"))
files+=list((R/"vendor/b/vectors").glob("*.hex"))+list((R/"vendor/b/python").rglob("*.py"))
files+=[R/"pds/program_ddr_camera_hires_prefetch.tcl",R/"scripts/program_ddr_camera_hires_prefetch.ps1",
    R/"scripts/record_prefetch_camera_program_20261012.py",R/"scripts/analyze_prefetch_camera_video_20261012.py",
    R/"scripts/analyze_clean_camera_video_20261011.py",R/"下载高清校正_连续读取版.cmd"]
with zipfile.ZipFile(release/"source_snapshot.zip","x",zipfile.ZIP_DEFLATED) as z:
    for p in dict.fromkeys(files):z.write(p,p.relative_to(R).as_posix())
with zipfile.ZipFile(release/"source_snapshot.zip") as z:assert z.testzip() is None
record={"sealed_at_utc":datetime.now(timezone.utc).isoformat(),"simulations_passed":True,"timing_passed":True,
 "part":"PG2L100H -6 FBG676","top":"video_correct_ddr_top","tests":tests,"base_release":"release/ddr_camera_hires_20261011",
 "source_sampling":[960,540],"processed_output":[640,904],"display":[1920,1080],"scale":1,
 "window":{"x":640,"y":88,"width":640,"height":904},"capture_fifo_packets":1024,
 "changed_sources":sorted(changed),"unchanged_compiled_source_count":len(unchanged),
 "change":"Read aligned eight-beat blocks only within completed-result banks, cache256 bytes, invalidate overlapping writes, retain single-command/response interface, and map display lines to Pango block RAM. Geometry/marker/input/HDMI configuration unchanged.",
 "retained_verified_baseline":"results/hardware_20261009/baseline_recovered_verified_20261012.json",
 "hardware_programmed":False,"actual_camera_correction_accepted":False,"clarity_improvement_accepted":False,"flash_modified":False,
 "performance_limit":"Shared-memory and refresh delays are test models; not measured DDR latency or algorithm FPS.",
 "timing_limit":"Vendor DDR and provisional external HDMI IO models; all constraints met under those models.",
 "files":{p.name:sha(p) for p in release.iterdir() if p.is_file()}}
(release/"build_qualification.json").write_text(json.dumps(record,indent=2)+"\n",encoding="utf-8")
print(json.dumps({"release":str(release),"sha256":sha(release/bit.name),"unchanged_sources":len(unchanged)},indent=2))
