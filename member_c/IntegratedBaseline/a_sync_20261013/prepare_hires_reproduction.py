"""Recreate A's pinned candidate and relocate only test/build paths."""
from pathlib import Path
import argparse, hashlib, json, re, subprocess

REV = "6b0b2e257efcfbb379d3f447403beb5ad08e0086"
PREFIX = "video_correct_integrated_20261008/"
OLD = "C:/D/FPGA/video_correct_integrated_20261008"
CANDIDATE = "diagnostics/ddr_camera_hires_prefetch_20261012/results/"

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    repo = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    def blob(p):
        return subprocess.check_output(["git", "show", f"{REV}:{PREFIX}{p}"], cwd=repo)
    files = set(p[len(PREFIX):] for p in subprocess.check_output(
        ["git", "ls-tree", "-r", "--name-only", REV, "--", PREFIX], cwd=repo,
        text=True).splitlines())
    hashes = json.loads(blob(CANDIDATE + "source_hashes.json"))
    production = {p.replace("\\", "/").split(PREFIX, 1)[1]: h for p,h in hashes.items()}
    pending = set(production) | {"constr/board_ddr.fdc"}
    pending |= {p for p in files if p.startswith(CANDIDATE) and (
        p.endswith((".sv", ".do", ".hex")) or p.rsplit("/",1)[-1] in
        {"build.tcl", "simulation_cases.json", "fixture.json", "configuration.json"})}
    records = {}
    while pending:
        p = pending.pop()
        if p in records:
            continue
        data = blob(p)
        original = hashlib.sha256(data).hexdigest()
        if p in production and original != production[p]:
            raise RuntimeError(f"Production hash mismatch: {p}")
        if p.endswith((".sv", ".do", ".tcl")):
            text = data.decode("utf-8-sig")
            for dep in re.findall(re.escape(OLD) + r'/([^{}"\s]+)', text):
                if dep in files and dep.endswith((".v", ".sv", ".vp", ".hex", ".fdc")):
                    pending.add(dep)
            text = text.replace(OLD, out.as_posix())
            data = text.encode("utf-8")
        target = (out / p).resolve()
        if not target.is_relative_to(out):
            raise RuntimeError(f"Unsafe source path: {p}")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        records[p] = {"upstream_sha256": original, "local_sha256": hashlib.sha256(data).hexdigest()}
    for p,h in production.items():
        if hashlib.sha256((out/p).read_bytes()).hexdigest()!=h:
            raise RuntimeError(f"Production source modified: {p}")
    tcl = (out/CANDIDATE/"build.tcl").read_text()
    designs = re.findall(r'add_design\s+\{([^}]+)\}', tcl)
    constraints = re.findall(r'add_constraint[^\n{]+\{([^}]+)\}', tcl)
    closure = designs + constraints
    if {Path(p).relative_to(out).as_posix() for p in closure} != set(production) or any(not Path(p).is_file() for p in closure):
        raise RuntimeError("Incomplete PDS source closure")
    (out/"reproduction_manifest.json").write_text(json.dumps({
        "upstream_commit": REV, "production_files": len(production),
        "path_relocation_only": True, "files": records}, indent=2)+"\n")
    print(f"Prepared {len(records)} inputs; {len(production)} production hashes unchanged; PDS closure complete.")

if __name__ == "__main__":
    main()
