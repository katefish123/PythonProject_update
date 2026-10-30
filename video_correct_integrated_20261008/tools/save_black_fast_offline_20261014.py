"""Preserve the qualified offline release; this script never accesses hardware."""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import zipfile

R = Path("C:/D/FPGA/video_correct_integrated_20261008")
D = R / "diagnostics/ddr_camera_black_fast_20261014"
RELEASE = R / "release/ddr_camera_black_fast_20261014"
STATE = R / "results/hardware_20261014_black_fast/black_fast_state_20261014.json"
BACKUP = R / "release/offline_black_fast_20261014_103248.zip"
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    assert not BACKUP.exists(), f"Existing archive must be preserved: {BACKUP}"
    q = json.loads((RELEASE / "build_qualification.json").read_text(encoding="utf-8"))
    assert q["simulations_passed"] and q["timing_passed"] and not q["hardware_programmed"]
    assert q["system_tests"] == 16 and q["whole_frame_exact_rgb_pixels"] == 578560
    for name, digest in q["files"].items():
        assert sha(RELEASE / name) == digest, name
    sources = json.loads((RELEASE / "source_hashes.json").read_text(encoding="utf-8"))
    sim = json.loads((RELEASE / "simulation_qualification.json").read_text(encoding="utf-8"))
    with zipfile.ZipFile(RELEASE / "source_snapshot.zip") as source_zip:
        assert source_zip.testzip() is None
        for path, digest in {**sources, **sim["verification_inputs"]}.items():
            source = Path(path)
            assert sha(source) == digest, path
            entry = source.relative_to(R).as_posix()
            assert hashlib.sha256(source_zip.read(entry)).hexdigest() == digest, entry
    old = R / "release/ddr_camera_black_20261014"
    old_q = json.loads((old / "build_qualification.json").read_text(encoding="utf-8"))
    for name, digest in old_q["files"].items():
        assert sha(old / name) == digest, f"Preserved release changed: {name}"
    for path, digest in json.loads((old / "source_hashes.json").read_text(encoding="utf-8")).items():
        assert sha(Path(path)) == digest, f"Preserved source changed: {path}"

    state = json.loads(STATE.read_text(encoding="utf-8"))
    assert state["user_confirmed_board_power_off"] and not state["new_candidate_programmed"]
    state.update({
        "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
        "phase": "offline_completed_board_off_by_user",
        "offline_build_passed": True,
        "timing_all_constraints_met": True,
        "release_file_check_passed": True,
        "baseline_release_files_and_sources_preserved": True,
        "bitstream_sha256": q["files"]["video_correct_ddr_top.sbit"],
        "build_qualification_sha256": sha(RELEASE / "build_qualification.json"),
        "baseline_model_seconds": 12315382 / 27000000,
        "candidate_model_seconds": q["modeled_27mhz_seconds"],
        "model_processing_time_reduction_percent": 100 * (1 - 6393441 / 12315382),
        "current_program_resident": False,
        "thermal_improvement_measured": False,
        "offline_backup": str(BACKUP),
        "offline_backup_checksum_file": str(BACKUP.with_suffix(".zip.sha256")),
        "dynamic_counter_stimulus_prepared": True,
        "real_time_30fps_accepted": False,
        "free_rotation_360_accepted": False,
        "next_action": "Keep board off; before a later hardware test check cooling and live ADC temperature, then compare identical dynamic stimulus on both releases",
    })
    STATE.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    files = list(RELEASE.iterdir()) + list((D / "src").rglob("*"))
    for sub in ("rtl", "python", "sim", "scripts", "vectors", "examples", "docs"):
        files += list((D / "b_algorithm" / sub).rglob("*"))
    files += list((D / "b_algorithm").glob("*"))
    files += list(D.glob("*"))
    for pattern in ("*.sv", "*.do", "*.hex", "*.json", "*.tcl", "*.pds", "*.png"):
        files += list((D / "results").glob(pattern))
    files += [R / "README.md", STATE, Path(__file__),
              R / "docs/保存与接续_20261014.md", R / "docs/黑色角标提速_20261014.md",
              R / "docs/板卡测温_20261014.md", R / "docs/板卡测温_20261013.md",
              R / "下载黑色角标提速版.cmd", R / "显示黑标延迟测试图.cmd",
              R / "下载黑色角标校正.cmd", R / "显示黑色角标测试图.cmd", R / "打开FPGA测温工具.cmd",
              R / "results/hardware_20261014_black/black_camera_state_20261014.json"]
    files = [path for path in dict.fromkeys(files) if path.is_file() and "__pycache__" not in path.parts]
    manifest = {
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "release": str(RELEASE), "board_power_off_confirmed_by_user": True,
        "hardware_programmed": False, "actual_latency_measured": False,
        "release_and_baseline_integrity_checked": True,
        "files": {path.relative_to(R).as_posix(): sha(path) for path in files},
    }
    with zipfile.ZipFile(BACKUP, "x", zipfile.ZIP_DEFLATED) as archive:
        for path in files:
            archive.write(path, path.relative_to(R).as_posix())
        archive.writestr("offline_backup_manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    with zipfile.ZipFile(BACKUP) as archive:
        assert archive.testzip() is None
        for name, digest in manifest["files"].items():
            assert hashlib.sha256(archive.read(name)).hexdigest() == digest, name
    digest = sha(BACKUP)
    BACKUP.with_suffix(".zip.sha256").write_text(f"{digest}  {BACKUP.name}\n", encoding="utf-8")
    receipt = {
        "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
        "backup": str(BACKUP), "sha256": digest, "bytes": BACKUP.stat().st_size,
        "archive_crc_and_all_file_hashes_verified": True, "files_preserved": len(files),
        "compiled_sources_and_verification_inputs_verified_in_source_snapshot": True,
        "baseline_release_and_sources_preserved": True, "hardware_programmed": False,
    }
    (STATE.parent / "offline_save_receipt_20261014.json").write_text(
        json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
