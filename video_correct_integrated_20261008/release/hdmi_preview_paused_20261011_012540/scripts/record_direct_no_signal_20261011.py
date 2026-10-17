"""Preserve the user-reported current bypass test without changing hardware or OBS."""
from datetime import datetime, timezone
from pathlib import Path
import json
import shutil

root = Path(__file__).resolve().parents[1]
hardware = root / "results/hardware_20261009"
timestamp = datetime.now(timezone.utc).isoformat()
pending = (
    "User-operated direct R50-to-capture recovery: power camera off, reseat the "
    "camera-side HDMI connector, power on to movie live view, wait 10 seconds; "
    "keep OBS 1080p30 MJPEG unchanged and desktop automation paused"
)
observation = {
    "recorded_at_utc": timestamp,
    "route_reported_by_user": "R50 HDMI directly to VC-002Pro HDMI input; USB to PC; FPGA bypassed",
    "source": "User reply to direct-camera-to-capture comparison",
    "user_report_verbatim": "未识别到信号视频输入",
    "actual_camera_display_accepted": False,
    "capture_usb_present_readonly_check": True,
    "capture_usb_status": "OK",
    "capture_usb_instance": "USB\\VID_345F&PID_2132&MI_00\\7&39AE5DB8&0&0000",
    "obs_capture_format_last_verified": "1920x1080 MJPEG 30fps",
    "additional_obs_log_findings": (
        "MJPEG decode errors and EOI warnings also occur after the 30fps change "
        "at 00:37-00:38; EOI warnings at 00:45. Root cause remains unproven."
    ),
    "scope_of_inference": (
        "The current failure also occurs with FPGA bypassed. This does not prove "
        "the FPGA camera or native-HDMI paths are correct, and does not distinguish "
        "camera output, HDMI cable/handshake, capture hardware or capture settings."
    ),
    "programmed_image_changed": False,
    "obs_configuration_changed": False,
    "computer_use_paused_by_user": True,
    "pending": pending,
}
observation_path = hardware / "camera_direct_no_signal_20261011.json"
observation_path.write_text(json.dumps(observation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

source_log = root / "tools/obs-studio/portable/config/obs-studio/logs/2026-10-10 19-51-31.txt"
if source_log.is_file():
    shutil.copyfile(source_log, hardware / "obs_after_direct_no_signal_20261011.txt")

record_path = hardware / "camera_flicker_state_20261011.json"
record = json.loads(record_path.read_text(encoding="utf-8-sig"))
record.update(
    utc=timestamp,
    direct_camera_to_capture_user_result=observation["user_report_verbatim"],
    direct_camera_to_capture_evidence=str(observation_path.relative_to(root)),
    current_direct_camera_to_capture_accepted=False,
    additional_obs_log_findings=observation["additional_obs_log_findings"],
    computer_use_paused_by_user=True,
    pending=pending,
)
record_path.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

status_path = root / "docs/hardware_20261009.json"
status = json.loads(status_path.read_text(encoding="utf-8-sig"))
status.update(
    last_update_utc=timestamp,
    direct_camera_to_capture_user_result=observation["user_report_verbatim"],
    current_direct_camera_to_capture_accepted=False,
    computer_use_paused_by_user=True,
    pending=pending,
)
status_path.write_text(json.dumps(status, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

prefix = """## 2026-10-11 当前直连对照仍无信号

用户将R50直接接采集卡、绕过FPGA，OBS保持1080p30/MJPEG后，报告“未识别到信号视频输入”。只读检查确认VC-002Pro仍在系统中且状态OK。说明这次问题在绕过FPGA时仍然存在，但不能由此证明FPGA视频链路正确，也不能单独判定相机、线缆、HDMI协商或采集配置哪项出错。30fps变更之后日志仍有少量EOI/解码错误，不能称采集解码已经完全稳定。

板上仍保留be1双BRAM接收诊断，未重新烧录、未修改OBS配置，桌面控制按用户要求停用。下一步请用户保持直连，关机重插相机端HDMI，再开到短片取景作一次重新连接检查；恢复真实直连画面后才继续验证FPGA输入。当前依据为`results/hardware_20261009/camera_direct_no_signal_20261011.json`与`camera_flicker_state_20261011.json`，以下为历史阶段记录。

"""
for name in ["docs/继续工作.md", "README.md", "docs/高清预览联调_20261010.md"]:
    path = root / name
    before = path.read_text(encoding="utf-8-sig")
    if "## 2026-10-11 当前直连对照仍无信号" not in before:
        first, separator, rest = before.partition("\n")
        path.write_text(first + separator + "\n" + prefix + rest.lstrip("\n"), encoding="utf-8")
print("Saved current user-reported bypass failure; hardware and OBS unchanged.")
