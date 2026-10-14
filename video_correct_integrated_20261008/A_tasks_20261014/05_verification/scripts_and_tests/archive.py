"""Seal a new black-marker release only after tests, timing and source checks."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import re
import shutil
import zipfile
from build import read

D = Path(__file__).resolve().parent
R = D.parents[1]
O = D / "results"
RELEASE = R / "release/ddr_camera_black_20261014"
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    sim = json.loads(read(O / "simulation_qualification.json"))
    cases = json.loads(read(O / "simulation_cases.json"))
    assert set(sim["tests"]) == set(cases)
    for item in sim["tests"].values():
        path = Path(item["log"])
        text = read(path)
        assert item["passed"] and sha(path) == item["log_sha256"]
        assert item["pass_message"] in text and "VERIFIED_PASS_BIT=1" in text
        assert not re.search(r"\*\* (Warning|Error|Fatal)|FAIL_", text)
    b = json.loads(read(O / "b_qualification.json"))
    assert b["native_modelsim_passed"] and b["test_count"] == 9 and b["python"]["python_tests"] == 17
    assert sha(Path(b["log"])) == b["log_sha256"]
    sources = json.loads(read(O / "source_hashes.json"))
    assert sim["source_hashes"] == sources
    for path, digest in sources.items():
        assert sha(Path(path)) == digest, path
    old = json.loads(read(R / "release/ddr_camera_coordqueue_20261013/source_hashes.json"))
    for path, digest in old.items():
        assert sha(Path(path)) == digest, f"Preserved baseline changed: {path}"
    config = json.loads(read(O / "configuration.json"))
    local_config = json.loads(read(D / "config.json"))
    assert all(config[key] == value for key, value in local_config.items())
    timing = O / "report_timing/video_correct_ddr_top.rtr"
    assert "Design Summary : All Constraints Met." in read(timing)
    assert "Executing : gen_bit_stream successfully." in read(O / "build_run.log")
    bit = O / "generate_bitstream/video_correct_ddr_top.sbit"
    mask = bit.with_suffix(".smsk")
    assert bit.stat().st_size == mask.stat().st_size == 3791112
    full = read(O / "tb_ddr_full_frame.run.log")
    assert "DDR_FULL_FRAME_PASS pixels=578560" in full
    cycles = int(re.search(r"DDR_FULL_FRAME_CYCLES=(\d+)", full)[1])
    RELEASE.mkdir(exist_ok=False)
    files = [bit, mask, timing, O/"build_run.log", O/"simulation_qualification.json", O/"b_qualification.json",
             O/"b_native_checks.log", O/"b_python_checks.log", O/"configuration.json", O/"fixture.json", O/"source_hashes.json",
             D/"config.json", D/"README.md", O/"black_correction_preview.png", O/"camera_target_1920x1080.png",
             O/"roi_guide_960x540.png", O/"expected_640x904.png"]
    files += [Path(test["log"]) for test in sim["tests"].values()]
    files += [O/"place_route/video_correct_ddr_top.prr", O/"place_route/video_correct_ddr_top_timing_summary_after_hold_fix.txt"]
    for path in files:
        shutil.copyfile(path, RELEASE / path.name)
    closure = list((D/"src").rglob("*"))
    closure += [p for sub in ("rtl", "python", "sim", "scripts", "vectors", "examples") for p in (D/"b_algorithm"/sub).rglob("*")]
    closure += list((D/"b_algorithm").glob("*")) + list((D/"b_algorithm/docs").rglob("*"))
    closure += list(D.glob("*.py")) + list(D.glob("*.ps1")) + [D/"README.md", D/"config.json", D/"program.tcl"]
    closure += [p for pattern in ("*.sv", "*.do", "*.hex", "*.json", "*.tcl", "*.pds") for p in O.glob(pattern)]
    closure += [R/"下载黑色角标校正.cmd", R/"显示黑色角标测试图.cmd", R/"docs/黑色角标校正_20261014.md"]
    with zipfile.ZipFile(RELEASE/"source_snapshot.zip", "x", zipfile.ZIP_DEFLATED) as archive:
        for path in dict.fromkeys(closure):
            if path.is_file() and "__pycache__" not in path.parts:
                archive.write(path, path.relative_to(R).as_posix())
    with zipfile.ZipFile(RELEASE/"source_snapshot.zip") as archive:
        assert archive.testzip() is None
    record = {"sealed_at_utc": datetime.now(timezone.utc).isoformat(), "simulations_passed": True, "timing_passed": True,
              "part": "PG2L100H -6 FBG676", "top": "video_correct_ddr_top", "marker_mode": "black_rgb_with_spatial_rois",
              "upstream_repository": config["upstream_repository"], "upstream_commit": config["upstream_commit"],
              "base_release": "ddr_camera_coordqueue_20261013", "source_sampling": [960,540], "processed_output": [640,904],
              "hdmi_output": [1920,1080], "processing_clock_mhz": 27, "coordinate_lookahead_credits": 16,
              "b_native_tests": 9, "b_python_tests": 17, "system_tests": len(cases), "whole_frame_exact_rgb_pixels": 578560,
              "modeled_frame_cycles": cycles, "modeled_27mhz_seconds": cycles/27000000,
              "hardware_programmed": False, "actual_camera_correction_accepted": False, "flash_modified": False,
              "real_time_30fps_accepted": False, "free_rotation_360_accepted": False,
              "performance_limit": "Cycle result is a synthetic memory model, not a measured camera/board update rate.",
              "geometry_limit": "Four black centroids in fixed ROIs; text/shadows inside a ROI interfere. No identity encoding or global tracking.",
              "timing_limit": "All constraints met under the inherited Pango PHY and provisional HDMI external IO timing models.",
              "files": {p.name: sha(p) for p in RELEASE.iterdir() if p.is_file()}}
    (RELEASE/"build_qualification.json").write_text(json.dumps(record, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    (RELEASE/"SHA256SUMS.txt").write_text("".join(f"{digest}  {name}\n" for name, digest in record["files"].items()), encoding="utf-8")
    print(json.dumps({"release": str(RELEASE), "bitstream_sha256": sha(RELEASE/bit.name),
                      "hardware_programmed": False, "system_tests": len(cases)}, indent=2))


if __name__ == "__main__":
    main()
