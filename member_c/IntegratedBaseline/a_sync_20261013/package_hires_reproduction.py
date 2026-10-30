"""Recheck a completed local build and package its evidence (not board acceptance)."""
import argparse
import hashlib
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expected-tests", type=int, default=12)
    args = parser.parse_args()
    mp = args.root / "reproduction_manifest.json"
    manifest = read(mp)
    digest = sha(mp)
    for name, record in manifest["files"].items():
        require(sha(args.root / name) == record["local_sha256"], f"Input changed: {name}")
    candidate = args.root / "diagnostics/ddr_camera_hires_prefetch_20261012/results"
    sp = candidate / "reproduced_simulation_qualification.json"
    simulation = read(sp)
    build_path = args.build / "build_qualification.json"
    build = read(build_path)
    require(build.get('simulations_passed') is True and build.get('timing_passed') is True, 'Build qualification incomplete')
    if 'simulation_qualification_sha256' in build:
        require(build['simulation_qualification_sha256'] == sha(sp), 'Build used a different simulation qualification')
    for record in (simulation, build):
        require(record["source_manifest_sha256"] == digest, "Input manifest mismatch")
        require(record["upstream_commit"] == manifest["upstream_commit"], "Commit mismatch")
    require(simulation.get("status") == "passed", "Simulation incomplete")
    cases = read(candidate / "simulation_cases.json")
    require(len(cases) == args.expected_tests and set(simulation["tests"]) == set(cases), "Test set mismatch")
    files = {"reproduction_manifest.json": mp, "simulation_qualification.json": sp,
             "original_build_qualification.json": build_path}
    if manifest.get('configuration') == 'fullhd_source_portrait':
        for name in ('fixture.json','source_1920x1080.png','expected_640x904.png'):
            files['fixture/'+name] = args.root/'fullhd_tests'/name
    for name, test in simulation["tests"].items():
        log = Path(test["log"])
        content = log.read_text(encoding="utf-8-sig", errors="replace")
        require(test["passed"] and sha(log) == test["log_sha256"], f"Invalid evidence: {name}")
        require(cases[name] in content and "VERIFIED_PASS_BIT=1" in content, f"Missing pass: {name}")
        require(not any(s in content for s in ("FAIL_", "** Error", "** Fatal", "** Warning")), f"Diagnostic: {name}")
        files[f"logs/{name}.log"] = log
    timing = Path(build["timing_report"])
    log = Path(build["build_log"])
    require("Design Summary : All Constraints Met." in timing.read_text(), "Timing failed")
    require("Executing : gen_bit_stream successfully." in log.read_text(errors="replace"), "Build incomplete")
    files.update({"timing_summary.txt": timing, "build.log": log})
    for kind in ("sbit", "smsk"):
        artifact = build["artifacts"][kind]
        path = Path(artifact["path"])
        require(sha(path) == artifact["sha256"], f"Artifact changed: {kind}")
        files[path.name] = path
    args.output.mkdir(parents=True, exist_ok=False)
    for name, path in files.items():
        target = args.output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
    result = dict(qualified_at_utc=datetime.now(timezone.utc).isoformat(),
                  upstream_commit=manifest["upstream_commit"], source_manifest_sha256=digest,
                  configuration=manifest.get('configuration','upstream_hires_candidate'),
                  qualification_method=('bound_prebuild_simulation_and_postbuild_revalidation'
                    if 'simulation_qualification_sha256' in build else 'post_build_revalidation_with_bound_simulation_replay'),
                  simulations_passed=len(cases), timing_passed=True, hardware_accepted=False,
                  files={name: sha(args.output / name) for name in files})
    (args.output / "package_manifest.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"PACKAGE_VERIFIED {args.output}")


if __name__ == "__main__":
    main()
