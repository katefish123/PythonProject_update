"""Record the current actual receiver diagnostic, preserving route corrections."""
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
program = args.program_log.resolve()
assert program.parent == hardware.resolve()
text = program.read_text(encoding="utf-8-sig", errors="replace")
assert "COMMAND[Program] execute successfully" in text and "COMMAND[Verify] execute successfully" in text
assert not any(token in text for token in ["execute fail", "exec failed", "Fail to compare", "** Error"])
image = "release/camera_live_bram_reconnect_20261010/camera_live_bram_top.sbit"
digest = hashlib.sha256((root / image).read_bytes()).hexdigest()
assert digest == "be1a72cade3008e25cff3f6925bf6347fea8211da6e5447fdd82ef137e7f5212"
stamp = datetime.now(timezone.utc).isoformat()
pending = "User saves OBS source screenshot with verified FPGA route; decode real D104/B401 receiver state or confirm actual coarse camera image before proceeding to DDR/marker diagnosis. No desktop automation."
record = {
    "recorded_at_utc": stamp,
    "current_image": image, "current_image_sha256": digest,
    "program_log": str(program.relative_to(root)), "program_verify_passed": True,
    "program_log_sha256": hashlib.sha256(program.read_bytes()).hexdigest(),
    "flash_modified": False,
    "phase": "Actual FPGA receiver input diagnosis after physical rewire",
    "route_correction": "results/hardware_20261009/route_scope_correction_20261011.json",
    "earlier_today_camera_recordings_verified_scope": "Direct camera/capture only, not FPGA native or DDR",
    "previous_full_ddr_observation": "User reports continuous color bars with FPGA actually connected",
    "previous_full_ddr_release_retained": "release/ddr_camera_reconnect_20261011",
    "actual_camera_display_accepted": False,
    "actual_camera_correction_accepted": False,
    "current_receiver_probe_decoded": False,
    "paused_by_user": False, "resumed_by_user": True,
    "computer_use_paused_by_user": True,
    "pending": pending,
}
path = hardware / "receiver_diagnostic_after_rewire_20261011.json"
path.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
status_path = root / "docs/hardware_20261009.json"
status = json.loads(status_path.read_text(encoding="utf-8-sig"))
status.update(record,
    last_update_utc=stamp,
    current_temporary_image=image, current_temporary_image_sha256=digest,
    bitstream_sha256=digest,
    latest_camera_live_state=str(path.relative_to(root)),
    capture_result="New be1 actual receiver diagnostic Program/Verify passed; awaiting source PNG after verified physical FPGA routing",
    current_physical_video_route="R50 -> FPGA HDMI-IN -> FPGA HDMI-OUT -> VC-002Pro -> USB PC, user explicitly reconnected",
)
status_path.write_text(json.dumps(status, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
prefix = """## 2026-10-11 当前读取真实接收诊断

用户核实此前今天的相机录像并未经过板子；验证范围已更正为相机直连，不保留FPGA短时稳定资格。实际接回FPGA后完整a4bd7 DDR版一直彩条。为分清相机输入与DDR/角标处理，已重新下载保留的be1接收诊断版，新Program/Verify通过日志`PROGRAM_LOG`。当前板上为be1，完整DDR版本及全部源/发布保留。

等待用户保存OBS“截屏(源)”，读取真实D104/B401状态或核验较粗的真实取景。当前相机校正、FPGA原生预览连续稳定及更新帧率均未验收，桌面控制仍停用。状态为`results/hardware_20261009/receiver_diagnostic_after_rewire_20261011.json`，范围更正为`route_scope_correction_20261011.json`；以下为历史阶段记录。

""".replace("PROGRAM_LOG", program.name)
for name in ["README.md", "docs/继续工作.md", "docs/高清预览联调_20261010.md", "docs/相机校正接续_20261011.md"]:
    document = root / name
    before = document.read_text(encoding="utf-8-sig")
    if "## 2026-10-11 当前读取真实接收诊断" not in before:
        first, separator, rest = before.partition("\n")
        document.write_text(first + separator + "\n" + prefix + rest.lstrip("\n"), encoding="utf-8")
print("Recorded actual be1 diagnostic; direct-camera videos kept separate from unverified FPGA reception.")
