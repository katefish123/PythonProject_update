"""Gate and archive the measured-state DDR candidate without changing prior releases."""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import shutil
import zipfile

D = Path(__file__).resolve().parent
R = D.parents[1]
O = D / "results"
release = R / "release/ddr_camera_status_20261011"
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):
    raw = p.read_bytes()
    return raw.decode("utf-16") if raw.startswith((b"\xff\xfe", b"\xfe\xff")) else raw.decode("utf-8-sig", errors="replace")
tests = json.loads(read(O / "simulation_qualification.json"))
assert len(tests["tests"]) == 4 and all(t["passed"] for t in tests["tests"].values())
for test in tests["tests"].values():
    assert sha(Path(test["log"])) == test["log_sha256"]
timing = O / "report_timing/video_correct_ddr_top.rtr"
assert "Design Summary : All Constraints Met." in read(timing)
assert "Executing : gen_bit_stream successfully." in read(O / "build_run.log")
source_hashes = json.loads(read(O / "source_hashes.json"))
baseline = json.loads(read(R / "release/ddr_camera_reconnect_20261011/source_hashes.json"))
for path, digest in baseline.items():
    assert sha(Path(path)) == digest, path
changed_names = {"marker_detector.v", "b_rectifier.v", "frame_processor.v", "frame_session.v",
    "ddr_snapshot_capture.v", "ddr_capture_writer.v", "video_correct_ddr_core.v", "video_correct_ddr_top.v"}
new_names = {"cdc_snapshot.v", "ddr_status_overlay.v"}
unchanged = []
changed = []
for path, digest in source_hashes.items():
    p = Path(path)
    assert sha(p) == digest, path
    if p.name in changed_names:
        assert p.parent == O
        originals = [Path(q) for q in baseline if Path(q).name == p.name]
        assert len(originals) == 1 and sha(originals[0]) != digest
        changed.append(p.name)
    elif p.name in new_names:
        assert p.parent in [O, D]
    else:
        assert baseline.get(path) == digest, path
        unchanged.append(path)
assert set(changed) == changed_names
release.mkdir(exist_ok=False)
for extension in ["sbit", "smsk"]:
    p = O / f"generate_bitstream/video_correct_ddr_top.{extension}"
    assert p.stat().st_size == 3791112
    shutil.copyfile(p, release / p.name)
for p in [timing, O / "build_run.log", O / "source_hashes.json", O / "simulation_qualification.json"] + [Path(t["log"]) for t in tests["tests"].values()]:
    shutil.copyfile(p, release / p.name)
files = [Path(p) for p in source_hashes] + list(D.glob("*.py")) + list(D.glob("*.ps1")) + list(D.glob("*.sv"))
files += [O / "build.tcl", O / "simulation_cases.json"] + list(O.glob("tb*.sv")) + list(O.glob("tb*.do"))
files += [R / "pds/program_ddr_camera_status.tcl", R / "scripts/program_ddr_camera_status.ps1"]
with zipfile.ZipFile(release / "source_snapshot.zip", "x", zipfile.ZIP_DEFLATED) as archive:
    for p in dict.fromkeys(files):
        archive.write(p, p.relative_to(R).as_posix())
with zipfile.ZipFile(release / "source_snapshot.zip") as archive:
    assert archive.testzip() is None
record = {
    "recorded_at_utc": datetime.now(timezone.utc).isoformat(), "simulations_passed": True, "timing_passed": True,
    "tests": tests, "part": "PG2L100H -6 FBG676", "top": "video_correct_ddr_top",
    "base_release": "release/ddr_camera_reconnect_20261011", "base_image_sha256": "a4bd7f42732c100b598cb974e03477877aab4032e39f6de558bb245d666e232e",
    "instrumented_modules": sorted(changed), "unchanged_compiled_source_count": len(unchanged),
    "source_sampling": [640, 480], "processed_output": [320, 452], "display": [1920, 1080],
    "change": "Expose actual capture outcomes, DDR drain progress, processor state/errors and inclusive marker counts/spans; coherently snapshot by clock domain and overlay D205 at y720..1039. Thresholds and processing behavior retained.",
    "hardware_programmed": False, "actual_camera_correction_accepted": False, "flash_modified": False,
    "timing_limit": "Vendor DDR and provisional external HDMI IO models; current real-camera DDR correction not accepted by simulation/timing alone.",
    "files": {p.name: sha(p) for p in release.iterdir() if p.is_file()},
}
(release / "build_qualification.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"release": str(release), "sbit_sha256": record["files"]["video_correct_ddr_top.sbit"], "unchanged_compiled_source_count": len(unchanged)}, indent=2))
