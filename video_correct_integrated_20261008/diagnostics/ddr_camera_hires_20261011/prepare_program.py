"""Prepare a new programming entry; retained low-resolution entry stays intact."""
from pathlib import Path
D=Path(__file__).resolve().parent
R=D.parents[1]
for name in ["pds/program_ddr_camera_reconnect.tcl","scripts/program_ddr_camera_reconnect.ps1"]:
    original=R/name
    text=original.read_text(encoding="utf-8-sig")
    assert "ddr_camera_reconnect_20261011" in text
    destination=original.with_name(original.name.replace("ddr_camera_reconnect","ddr_camera_hires"))
    destination.write_text(text.replace("ddr_camera_reconnect","ddr_camera_hires"),encoding="utf-8")
entry=(R/"下载相机校正_重连版.cmd").read_bytes()
assert entry.count(b"program_ddr_camera_reconnect.ps1")==1
(R/"下载高清校正工程.cmd").write_bytes(entry.replace(b"program_ddr_camera_reconnect.ps1",b"program_ddr_camera_hires.ps1"))
print("Prepared independent high-detail qualified Program/Verify entry; CRAM only.")
