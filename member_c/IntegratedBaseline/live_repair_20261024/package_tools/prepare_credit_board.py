"""Create an isolated full board for the registered ACK-slot timing hypothesis."""
from pathlib import Path
import argparse
import json
import shutil
from prepare_writer_credit import sha, transform

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--baseline", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    a = ap.parse_args()
    base, out = a.baseline.resolve(), a.output.resolve()
    manifest = json.loads((base/"source_manifest.json").read_text())
    if "display_lookahead" not in manifest or "writer_credit" in manifest:
        raise RuntimeError("Expected unmodified four-row candidate")
    for name, value in manifest["candidate_source_sha256"].items():
        if sha(base/"sources"/name) != value:
            raise RuntimeError("Parent drift: "+name)
    out.mkdir(parents=True, exist_ok=False)
    (out/"build").mkdir()
    shutil.copytree(base/"sources", out/"sources")
    name = "ddr_result_writer_burst64.v"
    writer = out/"sources"/name
    writer.write_text(transform(writer.read_text()))
    manifest["changed"].append(name)
    manifest["writer_credit"] = {
        "parent": str(base), "parent_manifest_sha256": sha(base/"source_manifest.json"),
        "old_sha256": sha(base/"sources"/name), "new_sha256": sha(writer),
        "generator_sha256": sha(Path(__file__).with_name("prepare_writer_credit.py")),
        "scope": "Register exclusive ACK-slot grant; one extra UI cycle after response, no math/clock/FDC changes",
    }
    manifest["candidate_source_sha256"] = {p.name: sha(p) for p in (out/"sources").iterdir()}
    (out/"source_manifest.json").write_text(json.dumps(manifest, indent=2)+"\n")
    (out/"build.tcl").write_text((base/"build.tcl").read_text().replace(base.as_posix(), out.as_posix()))
    print(out)
