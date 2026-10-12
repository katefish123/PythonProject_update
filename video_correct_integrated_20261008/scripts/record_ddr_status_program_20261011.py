"""Record the actually programmed DDR observer, keeping prior camera measurements."""
import argparse
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json

parser = argparse.ArgumentParser()
parser.add_argument("program_log", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
log = args.program_log.resolve()
assert log.parent == root / "results/hardware_20261009"
text = log.read_text(encoding="utf-8-sig", errors="replace")
image = "release/ddr_camera_status_20261011/video_correct_ddr_top.sbit"
assert (root / image).as_posix() in text
assert "COMMAND[Program] execute successfully" in text and "COMMAND[Verify] execute successfully" in text
assert not any(token in text for token in ["execute fail", "exec failed", "Fail to compare", "** Error"])
digest = hashlib.sha256((root / image).read_bytes()).hexdigest()
assert digest == "79edec3bb9730776f75ee204832b8884c69e74700c297046bde7cff9d5c2397b"
stamp = datetime.now(timezone.utc).isoformat()
record = {
    "recorded_at_utc": stamp, "current_image": image, "current_image_sha256": digest,
    "program_log": str(log.relative_to(root)), "program_log_sha256": hashlib.sha256(log.read_bytes()).hexdigest(),
    "program_verify_passed": True, "flash_modified": False,
    "phase": "Measure real full-DDR capture, marker detection and processor result with D205",
    "last_live_camera_input_evidence": "results/hardware_20261009/live_camera_input_verified_20261011.json",
    "retained_coarse_preview": "release/camera_live_bram_reconnect_20261010/camera_live_bram_top.sbit",
    "retained_clean_ddr_image": "release/ddr_camera_reconnect_20261011/video_correct_ddr_top.sbit",
    "actual_camera_display_accepted_for_current_image": False, "actual_camera_correction_accepted": False,
    "current_boot_ddr_bist_observed": False, "current_receiver_probe_decoded": False,
    "current_valid_camera_width_height_measured": False,
    "actual_camera_ddr_complete_capture_observed": False, "actual_target_correction_observed": False,
    "current_failed_stage": None, "decoded_samples": 0,
    "capture_counter_first_last": None, "capture_bad_count": None, "successful_result_count": None,
    "marker_observation": None,
    "last_complete_ddr_capture_evidence": "results/hardware_20261009/ddr_status_fpga_20261011_143638.json",
    "current_boot_measurement_limit": "New programming resets board state. Previous input, BIST, capture and marker observations are historical until a new real D205 recording is decoded.",
    "paused_by_user": False, "resumed_by_user": True, "computer_use_paused_by_user": True,
    "original_A_B_C_modified": False, "original_target_modified": False, "esc_behavior_modified": False,
    "pending": "User manually refreshes OBS source, records real four-marker target for about 30 seconds through the verified FPGA route; decode actual D205 capture/marker/processor state. No desktop automation.",
}
path = root / "results/hardware_20261009/ddr_camera_status_state_20261011.json"
path.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
status_path = root / "docs/hardware_20261009.json"
status = json.loads(status_path.read_text(encoding="utf-8-sig"))
status.update(record, last_update_utc=stamp, current_temporary_image=image,
    current_temporary_image_sha256=digest, bitstream_sha256=digest,
    latest_camera_live_state=str(path.relative_to(root)), actual_camera_display_accepted=False,
    capture_result="D205 full-DDR observer Program/Verify passed; current boot BIST, capture and real correction await actual target recording.")
status_path.write_text(json.dumps(status, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
prefix = """## 2026-10-11 当前为完整DDR状态诊断副本

当前板上为`release/ddr_camera_status_20261011`，Program/Verify已通过。该副本在a4完整工程上记录实际DDR整帧采集、写入进度、处理状态及角标像素数量/范围，并在y720..1039叠加D205红绿格；原阈值与处理流程保留。四项新仿真（包括缺角标保留旧结果）和PDS时序通过，8个模块增加观测输出，101个其余编译文件保持不变；未改原始A/B/C、旧发布、测试图及Esc行为，未写Flash。

此前独立b6f粗预览实录的18个样本均测得1920×1080，有真实取景变化，接收有效；证据为`results/hardware_20261009/live_camera_input_verified_20261011.json`。这不等于当前完整工程的DDR/算法已验收。等待经过板子的四色测试图录像，读取真实D205数据；桌面控制仍停用。当前状态为`results/hardware_20261009/ddr_camera_status_state_20261011.json`；下文为历史阶段记录。

"""
for name in ["README.md", "docs/继续工作.md", "docs/相机校正接续_20261011.md"]:
    document = root / name
    before = document.read_text(encoding="utf-8-sig")
    if "## 2026-10-11 当前为完整DDR状态诊断副本" not in before:
        first, separator, rest = before.partition("\n")
        document.write_text(first + separator + "\n" + prefix + rest.lstrip("\n"), encoding="utf-8")
print("Recorded programmed real DDR observer; no camera correction accepted without physical evidence.")
