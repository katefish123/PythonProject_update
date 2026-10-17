"""Record the actual new native download log, without reusing an old program result."""
import argparse
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json

parser = argparse.ArgumentParser()
parser.add_argument("program_log", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
hardware = root / "results/hardware_20261009"
log = args.program_log.resolve()
assert log.parent == hardware.resolve(), log
text = log.read_text(encoding="utf-8-sig", errors="replace")
assert "COMMAND[Program] execute successfully" in text
assert "COMMAND[Verify] execute successfully" in text
assert not any(token in text for token in ["execute fail", "exec failed", "Fail to compare", "** Error"])
image = "release/camera_native_rx_first_20261010/camera_native_rx_first_top.sbit"
digest = hashlib.sha256((root / image).read_bytes()).hexdigest()
assert digest == "b918087a2ec5179e78f1a3f78e903538e401abbc120ba40201abb45a9fb5cbc2"
stamp = datetime.now(timezone.utc).isoformat()
pending = "User checks new native image with camera and cables unchanged, no additional KEY0 or restart, waits 10 seconds and saves OBS source screenshot; desktop automation remains paused"
record = {
    "recorded_at_utc": stamp,
    "current_image": image,
    "current_image_sha256": digest,
    "program_log": str(log.relative_to(root)),
    "program_verify_passed": True,
    "flash_modified": False,
    "native_rgb888_every_pixel": True,
    "downsample_or_upscale": False,
    "config_order": "RX first, then TX, then return to RX with deferred-request replay",
    "previous_current_round_bram_display_accepted": True,
    "previous_current_round_bram_evidence": "results/hardware_20261009/bram_camera_recovered_20261011.json",
    "actual_camera_display_accepted": False,
    "clarity_accepted": False,
    "continuous_camera_display_verified": False,
    "actual_camera_correction_accepted": False,
    "current_receiver_probe_decoded": False,
    "computer_use_paused_by_user": True,
    "pending": pending,
    "rollback_image": "release/camera_live_bram_reconnect_20261010/camera_live_bram_top.sbit",
    "rollback_entry": "恢复相机预览_重连修正版.cmd",
    "original_A_B_C_modified": False,
    "esc_behavior_modified": False,
    "obs_configuration_changed": False,
}
path = hardware / "camera_native_comparison_state_20261011.json"
path.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

flicker_path = hardware / "camera_flicker_state_20261011.json"
state = json.loads(flicker_path.read_text(encoding="utf-8-sig"))
state.update(record, last_update_utc=stamp, latest_native_comparison_evidence=str(path.relative_to(root)))
flicker_path.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
status_path = root / "docs/hardware_20261009.json"
status = json.loads(status_path.read_text(encoding="utf-8-sig"))
status.update(
    last_update_utc=stamp,
    current_temporary_image=image,
    current_temporary_image_sha256=digest,
    bitstream_sha256=digest,
    latest_camera_live_state=str(path.relative_to(root)),
    native_rx_first_preview_programmed=True,
    native_rx_first_preview_verify_passed=True,
    native_rx_first_preview_sha256=digest,
    latest_native_program_log=str(log.relative_to(root)),
    actual_camera_display_accepted=False,
    clarity_accepted=False,
    continuous_camera_display_verified=False,
    actual_camera_correction_accepted=False,
    current_receiver_probe_decoded=False,
    previous_current_round_bram_display_accepted=True,
    capture_result="New native Program/Verify passed after actual be1 camera recovery; current native image awaiting manual observation",
    computer_use_paused_by_user=True,
    pending=pending,
)
status_path.write_text(json.dumps(status, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

prefix = f"""## 2026-10-11 当前全像素版已重新下载

先保存真实直连和经过be1低分辨率预览的两张源图，确认用户报告的取景及放大像素块。随后相机和接线保持，重新下载资格通过的b918接收优先全RGB888版；本次Program/Verify均成功，实际新日志为`{log.name}`。当前板上为b918，be1取景证据仅代表此前版本。本次没有额外要求KEY0或相机重启，先观察自动初始化后画面，避免打断已恢复的连接。

等待用户确认当前高清实时画面和新源图，暂不宣称清晰度、连续稳定或透视校正验收。保留be1恢复入口和全部原材料，OBS参数保持，桌面控制仍停用。当前状态为`results/hardware_20261009/camera_native_comparison_state_20261011.json`；以下为历史阶段记录。

"""
for name in ["docs/继续工作.md", "README.md", "docs/高清预览联调_20261010.md"]:
    document = root / name
    before = document.read_text(encoding="utf-8-sig")
    if "## 2026-10-11 当前全像素版已重新下载" not in before:
        first, separator, rest = before.partition("\n")
        document.write_text(first + separator + "\n" + prefix + rest.lstrip("\n"), encoding="utf-8")
print("Recorded current b918 image using new successful Program/Verify log; physical image pending.")
