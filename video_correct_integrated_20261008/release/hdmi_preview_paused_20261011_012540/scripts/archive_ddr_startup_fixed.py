"""Preserve the new startup-fixed build without replacing the previous release."""
from pathlib import Path
import datetime
import hashlib
import json
import re
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "results/board_ddr_startup_fixed_20261009"
OUT = ROOT / "release/ddr_startup_fixed_20261009"
TOP = "video_correct_ddr_top"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def text(path):
    raw = path.read_bytes()
    return raw.decode("utf-16") if raw.startswith((b"\xff\xfe", b"\xfe\xff")) else raw.decode("utf-8-sig", errors="replace")


timing = BUILD / f"report_timing/{TOP}.rtr"
if "Design Summary : All Constraints Met." not in text(timing):
    raise RuntimeError("Final timing has not passed")
if "Executing : gen_bit_stream successfully." not in text(ROOT / "results/build_ddr_startup_fixed_20261009.log"):
    raise RuntimeError("Bitstream generation has not passed")

test_evidence = []
for order in ["rx_first", "tx_first"]:
    path = ROOT / f"results/hdmi_startup_fix/{order}.log"
    for marker in ["TEST_PASS_CONFIG", "TEST_PASS_BOOTSTRAP_NACK_RECOVERY", "TEST_PASS_POSTPROBE_NACK_FATAL", "TEST_PASS_NO_DEVICE"]:
        if marker not in text(path):
            raise RuntimeError(f"Missing {marker} in {path}")
    test_evidence.append({"path": path.relative_to(ROOT).as_posix(), "sha256": sha(path)})

sources = []
for line in (ROOT / "pds/build_board_ddr.tcl").read_text().splitlines():
    match = re.fullmatch(r"add_design \{(.+)\}", line)
    if match:
        path = Path(match[1])
        if path not in sources:
            sources.append(path)
OUT.mkdir(parents=True, exist_ok=True)
artifacts = []
for extension in ["sbit", "smsk"]:
    path = BUILD / f"generate_bitstream/{TOP}.{extension}"
    if path.stat().st_size != 3791112:
        raise RuntimeError("Unexpected programming-file size")
    dest = OUT / path.name
    shutil.copyfile(path, dest)
    artifacts.append({"path": dest.relative_to(ROOT).as_posix(), "sha256": sha(dest), "bytes": dest.stat().st_size})
for path in [timing, BUILD / f"device_map/{TOP}.dmr", ROOT / "constr/board_ddr.fdc", ROOT / "docs/hdmi_startup_fix_20261009.md"]:
    shutil.copyfile(path, OUT / path.name)

snapshot_files = sources + [ROOT / relative for relative in [
    "constr/board_ddr.fdc", "constr/board_bram.fdc", "pds/build_board_ddr.tcl",
    "scripts/prepare_ddr_build.py", "scripts/build_ddr_board.ps1",
    "scripts/prepare_ddr_ip.py", "rtl/memory/ddr3_ip/ddr3_ip.idf",
    "sim/tb_hdmi_config.sv", "sim/run_hdmi_config.do", "scripts/run_hdmi_config_tests.ps1",
    "docs/hdmi_startup_fix_20261009.md", "docs/ddr_ip_notes.md",
]]
with zipfile.ZipFile(OUT / "source_snapshot.zip", "w", zipfile.ZIP_DEFLATED) as archive:
    for path in dict.fromkeys(snapshot_files):
        archive.write(path, path.relative_to(ROOT).as_posix())
manifest = {
    "client_date": "2026-10-09", "utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "status": "startup_fixed_build_verified_camera_acceptance_pending",
    "part": "PG2L100H -6 FBG676", "top": TOP,
    "source_frame": [640, 480], "result_frame": [320, 452], "display": "1920x1080 nominal 60Hz",
    "changes": ["TX-first HDMI initialization", "10ms I2C post-reset settle", "scratch-probe retries separated from fatal post-probe NACK", "clean I2C reset"],
    "timing_status": "All Constraints Met under vendor PHY and provisional video IO models",
    "bitstreams": artifacts,
    "sources": [{"path": p.relative_to(ROOT).as_posix(), "sha256": sha(p)} for p in sources],
    "new_test_evidence": test_evidence,
    "previous_functional_evidence": "docs/ddr_stage_verification.json",
    "hardware_evidence": "docs/hardware_20261009.json",
    "source_snapshot_sha256": sha(OUT / "source_snapshot.zip"),
    "camera_end_to_end_accepted": False,
}
(OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({"release": str(OUT), "sources": len(sources), "bitstreams": artifacts}, indent=2))
