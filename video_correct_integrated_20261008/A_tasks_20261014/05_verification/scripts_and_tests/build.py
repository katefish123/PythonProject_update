"""Build only after native B and complete black-DDR regression pass."""
from pathlib import Path
import hashlib
import json
import re
import subprocess

D = Path(__file__).resolve().parent
O = D / "results"
PDS = Path("C:/pango/PDS_2022.2-SP6.4/bin/pds_shell.exe")
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()


def read(path):
    data = path.read_bytes()
    return data.decode("utf-16") if data.startswith((b"\xff\xfe", b"\xfe\xff")) else data.decode("utf-8-sig", errors="replace")


def main():
    b = json.loads(read(O / "b_qualification.json"))
    assert b["native_modelsim_passed"] and b["test_count"] == 9
    assert sha(Path(b["log"])) == b["log_sha256"]
    sim = json.loads(read(O / "simulation_qualification.json"))
    cases = json.loads(read(O / "simulation_cases.json"))
    assert set(sim["tests"]) == set(cases)
    for test in sim["tests"].values():
        log = Path(test["log"])
        assert test["passed"] and sha(log) == test["log_sha256"]
        assert test["pass_message"] in read(log) and "VERIFIED_PASS_BIT=1" in read(log)
    sources = json.loads(read(O / "source_hashes.json"))
    assert sources == sim["source_hashes"]
    for path, digest in sources.items():
        assert sha(Path(path)) == digest, path
    log = O / "build_run.log"
    print("BLACK_DDR_BUILD_STARTED: native B and all system checks passed", flush=True)
    with log.open("w", encoding="utf-8") as stream:
        result = subprocess.run([str(PDS), "-file", str(O / "build.tcl"), "-work_dir", str(O),
                                 "-project_name", "ddr_camera_black"], cwd=O, stdout=stream, stderr=subprocess.STDOUT)
    text = read(log)
    if result.returncode or "Executing : gen_bit_stream successfully." not in text:
        raise RuntimeError(f"Black DDR build failed. See {log}\n{text[-2000:]}")
    timing = O / "report_timing/video_correct_ddr_top.rtr"
    assert "Design Summary : All Constraints Met." in read(timing), timing
    print("BLACK_DDR_BUILD_PASS All Constraints Met", flush=True)


if __name__ == "__main__":
    main()
