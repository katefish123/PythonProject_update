"""Qualify and retain the full DDR reconnect build, preserving old releases."""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import re
import shutil
import zipfile

directory = Path(__file__).resolve().parent
root = directory.parents[1]
build = directory / "results"
release = root / "release/ddr_camera_reconnect_20261011"

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def read(path):
    raw = path.read_bytes()
    return raw.decode("utf-16") if raw.startswith((b"\xff\xfe", b"\xfe\xff")) else raw.decode("utf-8-sig", errors="replace")

tests = json.loads(read(build / "simulation_qualification.json"))
assert len(tests["tests"]) == 3 and all(test["passed"] for test in tests["tests"].values())
for test in tests["tests"].values():
    assert sha(Path(test["log"])) == test["log_sha256"]
timing = build / "report_timing/video_correct_ddr_top.rtr"
assert "Design Summary : All Constraints Met." in read(timing)
assert "Executing : gen_bit_stream successfully." in read(build / "build_run.log")
source_hashes = json.loads(read(build / "source_hashes.json"))
for path, expected in source_hashes.items():
    assert sha(Path(path)) == expected, path

previous = json.loads(read(root / "release/ddr_startup_fixed_20261009/manifest.json"))
old_sources = {item["path"]: item["sha256"] for item in previous["sources"]}
unchanged = []
for path, digest in source_hashes.items():
    relative = Path(path).relative_to(root).as_posix()
    if relative == "diagnostics/ddr_camera_reconnect_20261011/results/ms7200_ctl.v" or relative == "constr/board_ddr.fdc":
        continue
    assert old_sources.get(relative) == digest, ("Unexpected unrelated source change", relative)
    unchanged.append(relative)

release.mkdir(parents=True, exist_ok=False)
for extension in ["sbit", "smsk"]:
    path = build / f"generate_bitstream/video_correct_ddr_top.{extension}"
    assert path.stat().st_size == 3791112
    shutil.copyfile(path, release / path.name)
for path in [timing, build / "build_run.log", build / "source_hashes.json", build / "simulation_qualification.json", build / "reconnect_change.diff", root / "constr/board_ddr.fdc"]:
    shutil.copyfile(path, release / path.name)
for test in tests["tests"].values():
    path = Path(test["log"])
    shutil.copyfile(path, release / path.name)
snapshot_files = [Path(path) for path in source_hashes]
snapshot_files += [directory / name for name in ["prepare.py", "run_checks.ps1", "build.ps1", "archive.py"]]
snapshot_files += [build / name for name in ["build.tcl", "ms7200_ctl_baseline.v", "tb_hdmi_config.sv", "tb_rx_reconnect.sv", "ms72xx_i2c_test_device.sv", "simulation_cases.json"]]
with zipfile.ZipFile(release / "source_snapshot.zip", "x", zipfile.ZIP_DEFLATED) as archive:
    for path in dict.fromkeys(snapshot_files):
        archive.write(path, path.relative_to(root).as_posix())
record = {
    "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
    "simulations_passed": True, "timing_passed": True,
    "tests": tests,
    "part": "PG2L100H -6 FBG676", "top": "video_correct_ddr_top",
    "source_snapshot": [640, 480], "processed_output": [320, 452],
    "output_hdmi": "1920x1080 nominal 60Hz; corrected result enlarged 2x",
    "change": "Previously proven receiver relock recovery extended to status 0x03; other compiled sources unchanged from retained DDR release",
    "unchanged_source_count": len(unchanged),
    "existing_algorithm_and_ddr_check_evidence": "docs/ddr_stage_verification.json; prior 8192-byte DDR BIST and internal fixture are historical, not current camera acceptance",
    "hardware_programmed": False,
    "actual_camera_correction_accepted": False,
    "flash_modified": False,
    "timing_limit": "Vendor DDR PHY constraints and provisional external HDMI IO model; requires new real-camera/DDR board validation",
    "files": {path.name: sha(path) for path in sorted(release.iterdir()) if path.is_file()},
}
(release / "build_qualification.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"release": str(release), "sbit_sha256": record["files"]["video_correct_ddr_top.sbit"], "smsk_sha256": record["files"]["video_correct_ddr_top.smsk"], "unchanged_source_count": len(unchanged)}, ensure_ascii=False, indent=2))
