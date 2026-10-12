"""Prepare independent, qualified-only programming and build entry points."""
from pathlib import Path

D=Path(__file__).resolve().parent
R=D.parents[1]
high=R/"diagnostics/ddr_camera_hires_20261011"
for name in ["prepare_fixture.py","tb_native_display.sv","tb_native_capture.sv"]:
    (D/name).write_bytes((high/name).read_bytes())
for name in ["run_checks.ps1","build.ps1"]:
    text=(high/name).read_text(encoding="utf-8-sig")
    text=text.replace("ddr_camera_hires","ddr_camera_hires_prefetch")
    if name=="build.ps1":
        text=text.replace("-ne 6","-ne 12").replace("Six high-detail","Twelve prefetch")
    (D/name).write_text(text,encoding="utf-8")
for relative in ["pds/program_ddr_camera_hires.tcl","scripts/program_ddr_camera_hires.ps1"]:
    old=R/relative
    destination=old.with_name(old.name.replace("ddr_camera_hires","ddr_camera_hires_prefetch"))
    text=old.read_text(encoding="utf-8-sig").replace("ddr_camera_hires","ddr_camera_hires_prefetch").replace("20261011","20261012")
    destination.write_text(text,encoding="utf-8")
entry=(R/"下载高清校正工程.cmd").read_bytes()
assert entry.count(b"program_ddr_camera_hires.ps1")==1
(R/"下载高清校正_连续读取版.cmd").write_bytes(entry.replace(b"program_ddr_camera_hires.ps1",b"program_ddr_camera_hires_prefetch.ps1"))
print("Prepared separate checked prefetch build/program entry; working baseline untouched.")
