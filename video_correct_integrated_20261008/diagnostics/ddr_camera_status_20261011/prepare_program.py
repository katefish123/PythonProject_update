"""Prepare only the independent qualified-release programming entry."""
from pathlib import Path
D = Path(__file__).resolve().parent
R = D.parents[1]
before = "ddr_camera_reconnect"
after = "ddr_camera_status"
for relative in ["pds/program_ddr_camera_reconnect.tcl", "scripts/program_ddr_camera_reconnect.ps1"]:
    original = R / relative
    text = original.read_text(encoding="utf-8-sig")
    assert "ddr_camera_reconnect_20261011" in text
    target = original.with_name(original.name.replace(before, after))
    assert target != original
    target.write_text(text.replace(before, after), encoding="utf-8")
print("Prepared qualified DDR status Program/Verify entry; CRAM only.")
