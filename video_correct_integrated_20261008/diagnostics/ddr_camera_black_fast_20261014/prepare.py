"""Snapshot the sealed black build without modifying its sources or evidence."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import shutil
import re

D = Path(__file__).resolve().parent
R = D.parents[1]
BASE = D.parent / "ddr_camera_black_20261014"
O = D / "results"
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    O.mkdir(exist_ok=True)
    manifest = json.loads((BASE/"results/source_hashes.json").read_text(encoding="utf-8-sig"))
    for path, digest in manifest.items():
        assert sha(Path(path)) == digest, path
    assert not (D/"src").exists(), "Snapshot once; use refresh.py after editing the new sources."
    shutil.copytree(BASE/"src", D/"src")
    shutil.copytree(BASE/"b_algorithm", D/"b_algorithm", ignore=shutil.ignore_patterns("work*", "__pycache__", "results"))
    (D/"b_algorithm/results").mkdir()
    for pattern in ("*.sv", "*.do", "*.tcl", "*.hex", "*.png"):
        for p in (BASE/"results").glob(pattern):
            if p.name != "b_native.do":
                shutil.copyfile(p, O/p.name)
    for name in ("simulation_cases.json", "configuration.json", "fixture.json"):
        shutil.copyfile(BASE/"results"/name, O/name)
    for name in ("config.json", "verify.py", "build.py", "archive.py", "program.ps1", "program.tcl", "show_target.py", "rectify_image.py"):
        shutil.copyfile(BASE/name, D/name)
    paths = [p for p in D.rglob("*") if p.is_file() and p.suffix in (".v", ".sv", ".do", ".tcl", ".py", ".ps1", ".json")]
    for p in paths:
        if p.name in ("prepare.py", "profile_cache.py"):
            continue
        s = p.read_text(encoding="utf-8-sig")
        s = s.replace(BASE.as_posix(), D.as_posix()).replace(str(BASE).replace("\\", "\\\\"), str(D).replace("\\", "\\\\"))
        s = s.replace("release/ddr_camera_black_20261014", "release/ddr_camera_black_fast_20261014")
        s = s.replace("release\\ddr_camera_black_20261014", "release\\ddr_camera_black_fast_20261014")
        s = s.replace("ddr_camera_black.pds", "ddr_camera_black_fast.pds").replace('"ddr_camera_black"', '"ddr_camera_black_fast"')
        p.write_text(s, encoding="utf-8")
    record = {"baseline": str(BASE), "baseline_source_hashes": manifest,
              "prepared_at_utc": datetime.now(timezone.utc).isoformat(), "board_modified": False}
    (O/"baseline_receipt.json").write_text(json.dumps(record, indent=2)+"\n", encoding="utf-8")
    print(f"FAST_SNAPSHOT_READY {len(manifest)} source/constraint files")


if __name__ == "__main__":
    main()
