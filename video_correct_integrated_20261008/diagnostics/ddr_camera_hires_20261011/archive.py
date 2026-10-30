"""Seal the high-detail candidate only after six checks and full timing pass."""
from datetime import datetime,timezone
from pathlib import Path
import hashlib
import json
import shutil
import zipfile

D=Path(__file__).resolve().parent
R=D.parents[1]
O=D/"results"
release=R/"release/ddr_camera_hires_20261011"
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):
    raw=p.read_bytes()
    return raw.decode("utf-16") if raw.startswith((b"\xff\xfe",b"\xfe\xff")) else raw.decode("utf-8-sig",errors="replace")
tests=json.loads(read(O/"simulation_qualification.json"))
assert len(tests["tests"])==6 and all(t["passed"] for t in tests["tests"].values())
for test in tests["tests"].values():
    assert sha(Path(test["log"]))==test["log_sha256"]
timing=O/"report_timing/video_correct_ddr_top.rtr"
assert "Design Summary : All Constraints Met." in read(timing)
assert "Executing : gen_bit_stream successfully." in read(O/"build_run.log")
sources=json.loads(read(O/"source_hashes.json"))
baseline=json.loads(read(R/"release/ddr_camera_reconnect_20261011/source_hashes.json"))
for path,digest in baseline.items():assert sha(Path(path))==digest,path
changes={"video_correct_ddr_top.v","ddr_result_display.v","frame_processor.v"}
changed=[];unchanged=[]
for path,digest in sources.items():
    p=Path(path)
    assert sha(p)==digest,path
    if p.name in changes:
        assert p.parent==O
        originals=[Path(q) for q in baseline if Path(q).name==p.name]
        assert len(originals)==1 and sha(originals[0])!=digest
        changed.append(p.name)
    else:
        assert baseline.get(path)==digest,path
        unchanged.append(path)
assert set(changed)==changes
release.mkdir(exist_ok=False)
for suffix in ["sbit","smsk"]:
    path=O/f"generate_bitstream/video_correct_ddr_top.{suffix}"
    assert path.stat().st_size==3791112
    shutil.copyfile(path,release/path.name)
for path in [timing,O/"source_hashes.json",O/"build_run.log",O/"simulation_qualification.json",O/"configuration.json",O/"fixture.json"]+[Path(t["log"]) for t in tests["tests"].values()]:
    shutil.copyfile(path,release/path.name)
files=[Path(p) for p in sources]+list(D.glob("*.py"))+list(D.glob("*.ps1"))+list(D.glob("*.sv"))
files+=[O/"build.tcl",O/"simulation_cases.json",O/"ddr_camera_hires.pds"]+list(O.glob("tb*.sv"))+list(O.glob("tb*.do"))
files+=list(O.glob("*.hex"))+[R/"pds/program_ddr_camera_hires.tcl",R/"scripts/program_ddr_camera_hires.ps1",R/"下载高清校正工程.cmd"]
with zipfile.ZipFile(release/"source_snapshot.zip","x",zipfile.ZIP_DEFLATED) as archive:
    for path in dict.fromkeys(files):archive.write(path,path.relative_to(R).as_posix())
with zipfile.ZipFile(release/"source_snapshot.zip") as archive:assert archive.testzip() is None
record={"recorded_at_utc":datetime.now(timezone.utc).isoformat(),"simulations_passed":True,"timing_passed":True,
    "part":"PG2L100H -6 FBG676","top":"video_correct_ddr_top","tests":tests,
    "input":[1920,1080],"source_sampling":[960,540],"processed_output":[640,904],"display":[1920,1080],"scale":1,
    "window":{"x":640,"y":88,"width":640,"height":904},"capture_fifo_packets":1024,
    "changed_sources":sorted(changed),"unchanged_compiled_source_count":len(unchanged),
    "change":"Increase source sampling and result pixels; retain display window; parameter-sized row/beat counters; packed 256-bit line buffers store all eight pixels on one UI clock, with aligned pixel-lane selection.",
    "retained_verified_baseline":"results/hardware_20261009/working_clean_baseline_verified_20261011.json",
    "hardware_programmed":False,"actual_camera_correction_accepted":False,"clarity_improvement_accepted":False,"flash_modified":False,
    "performance_limit":"Simulation cycle count is not actual throughput. Higher result resolution can reduce completed-result update rate; requires real camera verification.",
    "timing_limit":"Vendor DDR and provisional external HDMI IO timing; all constraints met within those models.",
    "files":{p.name:sha(p) for p in release.iterdir() if p.is_file()}}
(release/"build_qualification.json").write_text(json.dumps(record,indent=2)+"\n",encoding="utf-8")
print(json.dumps({"release":str(release),"sbit_sha256":record["files"]["video_correct_ddr_top.sbit"],"unchanged_compiled_source_count":len(unchanged)},indent=2))
