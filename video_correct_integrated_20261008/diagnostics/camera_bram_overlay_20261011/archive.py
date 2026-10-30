"""Archive tested status overlay; retain existing releases and original projects."""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import shutil
import zipfile

D = Path(__file__).resolve().parent
R = D.parents[1]
O = D / "results"
release = R / "release/camera_bram_overlay_20261011"
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):
    data = p.read_bytes()
    return data.decode("utf-16") if data.startswith((b"\xff\xfe", b"\xfe\xff")) else data.decode("utf-8-sig", errors="replace")
tests = json.loads(read(O / "simulation_qualification.json"))
assert len(tests["tests"]) == 3 and all(t["passed"] for t in tests["tests"].values())
for test in tests["tests"].values():
    assert sha(Path(test["log"])) == test["log_sha256"]
timing = O / "report_timing/camera_live_bram_top.rtr"
assert "Design Summary : All Constraints Met." in read(timing)
assert "Executing : gen_bit_stream successfully." in read(O / "build_run.log")
sources = json.loads(read(O / "source_hashes.json"))
for path, digest in sources.items():
    assert sha(Path(path)) == digest, path
baseline = json.loads(read(R / "release/camera_live_bram_reconnect_20261010/source_hashes.json"))
old = {Path(p).name: digest for p, digest in baseline.items()}
unchanged = []
for path, digest in sources.items():
    if Path(path).name != "camera_live_bram_top.v":
        assert old[Path(path).name] == digest, path
        unchanged.append(Path(path).name)
release.mkdir(exist_ok=False)
for extension in ["sbit", "smsk"]:
    path = O / f"generate_bitstream/camera_live_bram_top.{extension}"
    assert path.stat().st_size == 3791112
    shutil.copyfile(path, release / path.name)
copy = [timing, O / "build_run.log", O / "source_hashes.json", O / "simulation_qualification.json", O / "overlay.diff"]
copy += [Path(t["log"]) for t in tests["tests"].values()]
for p in copy:
    shutil.copyfile(p, release / p.name)
files = [Path(p) for p in sources] + [D / name for name in ["prepare.py", "run_checks.ps1", "build.ps1", "archive.py"]]
files += [O / "build.tcl"] + list(O.glob("tb*.v")) + list(O.glob("tb*.do"))
files += [R / "scripts/program_camera_bram_overlay.ps1", R / "pds/program_camera_bram_overlay.tcl"]
with zipfile.ZipFile(release / "source_snapshot.zip", "x", zipfile.ZIP_DEFLATED) as archive:
    for path in dict.fromkeys(files):
        archive.write(path, path.relative_to(R).as_posix())
with zipfile.ZipFile(release / "source_snapshot.zip") as archive:
    assert archive.testzip() is None
record = {
    "utc": datetime.now(timezone.utc).isoformat(), "simulations_passed": True, "timing_passed": True,
    "part": "PG2L100H -6 FBG676", "top": "camera_live_bram_top", "tests": tests,
    "change": "Overlay real D104/B401 state at y840..1079 even while coarse camera image is valid; preserve camera pixels above y840.",
    "unchanged_compiled_sources": unchanged,
    "base_release": "release/camera_live_bram_reconnect_20261010",
    "base_sbit_sha256": "be1a72cade3008e25cff3f6925bf6347fea8211da6e5447fdd82ef137e7f5212",
    "hardware_programmed": False, "actual_camera_display_accepted": False, "actual_camera_correction_accepted": False,
    "flash_modified": False, "capture_size": [320, 180], "output_size": [1920, 1080],
    "timing_limit": "Provisional HDMI IO timing model; actual live receiver metrics and physical camera output still require verification.",
    "files": {p.name: sha(p) for p in release.iterdir() if p.is_file()},
}
(release / "build_qualification.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"release": str(release), "sbit_sha256": record["files"]["camera_live_bram_top.sbit"], "unchanged_compiled_source_count": len(unchanged)}, indent=2))
