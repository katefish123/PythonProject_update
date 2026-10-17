"""Record current manual direct-camera recovery, keeping FPGA acceptance separate."""
from datetime import datetime, timezone
from pathlib import Path
import json

root = Path(__file__).resolve().parents[1]
hardware = root / "results/hardware_20261009"
stamp = datetime.now(timezone.utc).isoformat()
pending = (
    "User saves direct-camera OBS source screenshot, reconnects R50 to FPGA HDMI-IN "
    "and FPGA HDMI-OUT to capture, keeps camera live and FPGA powered without KEY0, "
    "waits 10 seconds; save another source screenshot if diagnostic grid only. "
    "Desktop automation remains paused."
)
observation = {
    "recorded_at_utc": stamp,
    "source": "User reply after direct camera power-off, HDMI reseat and movie-mode restart",
    "user_report_verbatim": "出现真实取景",
    "route_reported_by_user": "R50 directly to VC-002Pro; FPGA bypassed",
    "obs_capture_format_last_verified": "1920x1080 MJPEG 30fps",
    "current_direct_camera_to_capture_accepted": True,
    "continuous_direct_camera_display_verified": False,
    "fpga_camera_display_accepted": False,
    "scope_of_inference": (
        "Direct camera, cable and capture can display a current real image after "
        "this recovery operation. This does not prove a specific root cause, "
        "long-term stability, FPGA video reception, native preview or correction."
    ),
    "previous_direct_failure_evidence": "results/hardware_20261009/camera_direct_no_signal_20261011.json",
    "screenshot_independently_verified": False,
    "programmed_image_changed": False,
    "obs_configuration_changed": False,
    "computer_use_paused_by_user": True,
    "pending": pending,
}
path = hardware / "camera_direct_recovered_20261011.json"
path.write_text(json.dumps(observation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
for relative in ["results/hardware_20261009/camera_flicker_state_20261011.json", "docs/hardware_20261009.json"]:
    status_path = root / relative
    status = json.loads(status_path.read_text(encoding="utf-8-sig"))
    status.update(
        last_update_utc=stamp,
        direct_camera_to_capture_user_result=observation["user_report_verbatim"],
        direct_camera_to_capture_evidence=str(path.relative_to(root)),
        current_direct_camera_to_capture_accepted=True,
        continuous_direct_camera_display_verified=False,
        computer_use_paused_by_user=True,
        pending=pending,
    )
    status_path.write_text(json.dumps(status, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

prefix = """## 2026-10-11 当前相机直连已恢复

用户保持R50直接接采集卡，关机重插相机端HDMI后重新进入短片取景，报告“出现真实取景”。这证明该次连接能够提供真实相机画面，不能单独确定掉线根因，也不代表FPGA取景、高清预览、透视校正或连续稳定验收通过。此刻结果来源为用户现场观察，尚无新源截图独立核验。

下一步请用户先在OBS保存直连源截图，再接回相机→FPGA HDMI-IN、FPGA HDMI-OUT→采集卡，保持电源和取景、不按KEY0作接回对照；若只有状态格，再保存源截图供解码。板上be1诊断及OBS设置保持，桌面控制继续停用。当前依据为`results/hardware_20261009/camera_direct_recovered_20261011.json`与`camera_flicker_state_20261011.json`；以下为历史阶段记录。

"""
for name in ["docs/继续工作.md", "README.md", "docs/高清预览联调_20261010.md"]:
    document = root / name
    before = document.read_text(encoding="utf-8-sig")
    if "## 2026-10-11 当前相机直连已恢复" not in before:
        first, separator, rest = before.partition("\n")
        document.write_text(first + separator + "\n" + prefix + rest.lstrip("\n"), encoding="utf-8")
print("Saved user-reported direct camera recovery; FPGA checks remain pending.")
