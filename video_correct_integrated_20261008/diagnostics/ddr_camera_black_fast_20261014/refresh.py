"""Invalidate qualifications and hash the final independent source closure."""
from pathlib import Path
import json
import re
import hashlib

D = Path(__file__).resolve().parent
O = D/"results"
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    for name in ("simulation_qualification.json", "focused_qualification.json"):
        (O/name).unlink(missing_ok=True)
    for p in list(O.glob("*.do"))+[O/"build.tcl"]:
        s = p.read_text(encoding="utf-8")
        s = s.replace("/src/rtl/memory/ddr_pixel_cache.v", "/src/rtl/memory/ddr_pixel_cache_fast.v")
        p.write_text(s, encoding="utf-8")
    s = (O/"build.tcl").read_text(encoding="utf-8")
    paths = [Path(m[1]) for line in s.splitlines() if (m := re.fullmatch(r"add_design \{(.+)\}", line))]
    paths.append(D/"src/constr/board_ddr.fdc")
    assert all(p.is_relative_to(D) for p in paths)
    (O/"source_hashes.json").write_text(json.dumps({str(p): sha(p) for p in paths}, indent=2)+"\n", encoding="utf-8")
    config = json.loads((O/"configuration.json").read_text(encoding="utf-8"))
    config.update({"baseline_release": "ddr_camera_black_20261014", "cache_level1_lines": 2,
                   "cache_level2_sets": 128, "cache_level2_ways": 2, "roi_scan_only": True,
                   "result_fifo_credits": 16, "overlap_interpolation_write_and_sampling": True,
                   "physical_acceptance": False})
    (O/"configuration.json").write_text(json.dumps(config, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(f"FAST_SOURCES_HASHED {len(paths)}")


if __name__ == "__main__":
    main()
