"""Copy an existing exact stimulus, changing only the ACK-slot grant register."""
from pathlib import Path
import argparse
import json
import shutil
from prepare_writer_credit import sha, transform

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--previous", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()
    previous = args.previous.resolve()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    shutil.copytree(previous/"source_snapshot", out/"source_snapshot")
    name = "ddr_result_writer_burst64.v"
    writer = out/"source_snapshot"/name
    writer.write_text(transform(writer.read_text()))
    for source in (previous/"source_snapshot").iterdir():
        if source.name != name and sha(source) != sha(out/"source_snapshot"/source.name):
            raise RuntimeError("Unexpected change: "+source.name)
    shutil.copyfile(previous/"run.ps1", out/"run.ps1")
    if (previous/"source_binding.json").is_file():
        shutil.copyfile(previous/"source_binding.json", out/"source_binding.json")
    (out/"credit_binding.json").write_text(json.dumps({
        "previous": str(previous), "previous_bench_sha256": sha(previous/"source_snapshot/tb_lens_board.sv"),
        "writer_old_sha256": sha(previous/"source_snapshot"/name), "writer_new_sha256": sha(writer),
        "transform_sha256": sha(Path(__file__).with_name("prepare_writer_credit.py")),
        "source_sha256": {p.name: sha(p) for p in (out/"source_snapshot").iterdir()},
        "hardware_acceptance": False, "physical_timing_qualified": False,
    }, indent=2)+"\n")
    print(out)
