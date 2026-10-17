"""Run native ModelSim black-algorithm and DDR-system checks with fresh evidence."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import re
import subprocess
import sys

D = Path(__file__).resolve().parent
O = D / "results"
B = D / "b_algorithm"
BIN = Path("C:/modeltech64_2020.4/win64")
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()


def run(command, cwd, log):
    with log.open("w", encoding="utf-8") as stream:
        result = subprocess.run([str(x) for x in command], cwd=cwd, stdout=stream, stderr=subprocess.STDOUT)
    text = log.read_text(encoding="utf-8-sig", errors="replace")
    if result.returncode or re.search(r"\*\* (?:Error|Fatal)|FAIL_", text):
        raise RuntimeError(f"Check failed: {log}\n{text[-2500:]}")
    return text


def algorithm():
    run([sys.executable, "-X", "utf8", "-B", "scripts/run_checks.py", "--python-only"], B, O/"b_python_checks.log")
    dofile = O / "b_native.do"
    tops = [line.split() for line in (B/"sim/tests.list").read_text().splitlines() if line.strip() and not line.startswith("#")]
    lines = ["onerror {quit -f -code 1}", "onbreak {resume}", "vlib work_black_b", "vmap work_black_b work_black_b"]
    for file in sorted((B/"rtl").glob("*.v")):
        lines.append(f"vlog -work work_black_b {{{file.as_posix()}}}")
    lines.append(f"vlog -work work_black_b {{{(B/'examples/b_rectifier_instance.v').as_posix()}}}")
    for file in sorted((B/"sim").glob("*.sv")):
        lines.append(f"vlog -sv -work work_black_b {{{file.as_posix()}}}")
    for top, marker in tops:
        lines += [f"vsim -voptargs=+acc work_black_b.{top}", "onfinish stop", "run -all",
                  f"set p [examine -value -radix binary -noshowbase sim:/{top}/test_passed]",
                  'if {[llength $p]!=1 || [lindex $p 0] ne "1"} {quit -f -code 1}',
                  f'puts "BLACK_NATIVE_VERIFIED {top}"', "quit -sim"]
    lines += ['puts "ALL_BLACK_NATIVE_CHECKS_PASS"', "quit -f -code 0"]
    dofile.write_text("\n".join(lines)+"\n", encoding="utf-8")
    log = O / "b_native_checks.log"
    text = run([BIN/"vsim.exe", "-c", "-do", dofile], B, log)
    for top, marker in tops:
        assert f"BLACK_NATIVE_VERIFIED {top}" in text and marker in text, top
    assert "ALL_BLACK_NATIVE_CHECKS_PASS" in text
    sys.path.insert(0, str(B/"scripts"))
    from run_checks import compare_dumps
    counts = compare_dumps()
    report = {"native_modelsim_passed": True, "test_count": len(tops), "actual_rtl_comparison": counts,
              "log": str(log), "log_sha256": sha(log), "python": json.loads((B/"results/verification.json").read_text())}
    (O/"b_qualification.json").write_text(json.dumps(report, indent=2)+"\n", encoding="utf-8")
    print(f"BLACK_B_PASS native_tests={len(tops)} actual_dumps={counts}", flush=True)


def system(selected):
    sources = json.loads((O/"source_hashes.json").read_text(encoding="utf-8-sig"))
    for path, digest in sources.items():
        assert sha(Path(path)) == digest, path
    cases = json.loads((O/"simulation_cases.json").read_text(encoding="utf-8-sig"))
    records = {}
    for top, marker in cases.items():
        if selected and top not in selected:
            continue
        log = O / f"{top}.run.log"
        text = run([BIN/"vsim.exe", "-c", "-do", f"{top}.do"], O, log)
        assert marker in text and "VERIFIED_PASS_BIT=1" in text, log
        assert not re.search(r"\*\* Warning", text), log
        records[top] = {"passed": True, "pass_message": marker, "log": str(log), "log_sha256": sha(log)}
        print(f"BLACK_SYSTEM_PASS {top}", flush=True)
    name = "focused_qualification.json" if selected else "simulation_qualification.json"
    (O/name).write_text(json.dumps({"qualified_at_utc": datetime.now(timezone.utc).isoformat(),
                         "tests": records, "source_hashes": sources, "hardware_accepted": False}, indent=2)+"\n", encoding="utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--algorithm-only", action="store_true")
    ap.add_argument("--system-only", action="store_true")
    ap.add_argument("--cases", nargs="*")
    args = ap.parse_args()
    if not args.system_only:
        algorithm()
    if not args.algorithm_only:
        system(args.cases)


if __name__ == "__main__":
    main()
