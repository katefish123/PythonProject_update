"""Prepare a clean high-detail read-ahead clone; preserve all proven releases."""
from pathlib import Path
import hashlib
import json
import re
import shutil

D=Path(__file__).resolve().parent
R=D.parents[1]
O=D/"results"
O.mkdir(exist_ok=True)
base=R/"release/ddr_camera_hires_20261011"
qualification=json.loads((base/"build_qualification.json").read_text(encoding="utf-8-sig"))
assert qualification["simulations_passed"] and qualification["timing_passed"]
baseline=json.loads((base/"source_hashes.json").read_text(encoding="utf-8-sig"))
for path,digest in baseline.items():assert hashlib.sha256(Path(path).read_bytes()).hexdigest()==digest,path
def original(name):
    paths=[Path(p) for p in baseline if Path(p).name==name]
    assert len(paths)==1,name
    return paths[0]
proto=R/"diagnostics/ddr_hires_read_ahead_20261011/results"
comparison=json.loads((proto/"display_engine_comparison.json").read_text(encoding="utf-8-sig"))
assert comparison["all_four_checks_passed"] and comparison["read_ahead_enabled"]["black_pixels"]==0
engine=proto/"ddr_word_engine.v"
assert hashlib.sha256(engine.read_bytes()).hexdigest()==comparison["source_hashes"][str(engine.relative_to(R))]
shutil.copyfile(engine,O/engine.name)
top_path=original("video_correct_ddr_top.v")
top=top_path.read_text(encoding="utf-8-sig")
assert top.count("ddr_word_engine engine(")==1
top=top.replace("ddr_word_engine engine(","ddr_word_engine #(.READ_AHEAD_ENABLE(1),.RESULT_WORDS(640*904)) engine(")
(O/top_path.name).write_text(top,encoding="utf-8")
display_path=original("ddr_result_display.v")
display=display_path.read_text(encoding="utf-8-sig")
assert display.count('(* ram_style="block", ramstyle="M20K" *)')==2
display=display.replace('(* ram_style="block", ramstyle="M20K" *)','(* syn_ramstyle="block_ram" *)')
(O/display_path.name).write_text(display,encoding="utf-8")
flow=(R/"diagnostics/ddr_camera_hires_20261011/results/build.tcl").read_text(encoding="utf-8-sig")
for p in [top_path,display_path,original("ddr_word_engine.v")]:
    before=f"add_design {{{p.as_posix()}}}"
    assert flow.count(before)==1,p
    flow=flow.replace(before,f"add_design {{{(O/p.name).as_posix()}}}")
(O/"build.tcl").write_text(flow,encoding="utf-8")
paths=[Path(m[1]) for line in flow.splitlines() if (m:=re.fullmatch(r"add_design \{(.+)\}",line))]
paths+=[R/"constr/board_ddr.fdc"]
(O/"source_hashes.json").write_text(json.dumps({str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},indent=2)+"\n",encoding="utf-8")
config=json.loads((R/"diagnostics/ddr_camera_hires_20261011/results/configuration.json").read_text(encoding="utf-8-sig"))
config.update(read_ahead_beats=8,result_cache_bytes=256,line_memory_style="Pango syn_ramstyle=block_ram",
    diagnostic_grid_present=False,physical_acceptance=False,base_release="release/ddr_camera_hires_20261011",
    note="Retain high source/result dimensions and all thresholds; optimize completed-result DDR reads without changing client API. Physically verified baseline remains available.")
(O/"configuration.json").write_text(json.dumps(config,indent=2)+"\n",encoding="utf-8")
print("Prepared independent clean high-detail prefetch clone: only engine, top enable and line RAM style changed.")
