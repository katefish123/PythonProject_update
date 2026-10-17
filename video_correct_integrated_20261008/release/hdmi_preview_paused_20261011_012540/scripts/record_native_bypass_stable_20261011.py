"""Keep the current stable NV12 bypass result separate from unstable FPGA video."""
from datetime import datetime, timezone
from pathlib import Path
import json

root = Path(__file__).resolve().parents[1]
hardware = root / "results/hardware_20261009"
stamp = datetime.now(timezone.utc).isoformat()
pending = "User verifies documented R50 FHD59.94/NTSC, HDMI1080p, camera+monitor, no auto-off settings against current stable direct capture; inspect FPGA native output clock/sync/IO and HDMI-OUT path next; desktop automation remains paused"
observation = {
    "recorded_at_utc": stamp,
    "source": "User reply to identical-NV12 direct-camera comparison",
    "user_report_verbatim": "取景稳定，不闪烁，但是你确定我相机调的对吗，要调哪些你完整说一遍",
    "route_reported_by_user": "R50 HDMI directly to capture; camera aimed away from computer display",
    "obs_settings": "1920x1080, 30fps, NV12",
    "settings_previously_verified_in_log_at": "2026-10-11 01:07:15.440 Asia/Shanghai",
    "manual_observation_requested_seconds": 20,
    "current_direct_camera_to_capture_accepted": True,
    "user_reported_short_direct_observation_stable": True,
    "all_camera_menu_values_independently_verified": False,
    "long_term_stability_verified": False,
    "fpga_native_display_stability_accepted": False,
    "actual_camera_correction_accepted": False,
    "scope_of_inference": (
        "Native FPGA path flickers under MJPEG and NV12; the same NV12 capture "
        "settings produce a user-reported stable direct-camera image. Focus "
        "investigation on the FPGA-inclusive path, including HDMI-OUT cable; "
        "this does not prove a specific FPGA code or clock defect."
    ),
    "current_physical_video_route": "R50 direct to capture, FPGA bypassed",
    "current_fpga_image": "release/camera_native_rx_first_20261010/camera_native_rx_first_top.sbit",
    "camera_checklist": "docs/R50相机与OBS设置_20261011.md",
    "computer_use_paused_by_user": True,
    "pending": pending,
}
path = hardware / "native_nv12_direct_stable_20261011.json"
path.write_text(json.dumps(observation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
for relative in ["results/hardware_20261009/camera_native_comparison_state_20261011.json", "results/hardware_20261009/camera_flicker_state_20261011.json", "docs/hardware_20261009.json"]:
    status_path = root / relative
    status = json.loads(status_path.read_text(encoding="utf-8-sig"))
    status.update(
        last_update_utc=stamp,
        current_physical_video_route=observation["current_physical_video_route"],
        direct_camera_to_capture_user_result="NV12 direct camera stable, no flicker",
        direct_camera_to_capture_evidence=str(path.relative_to(root)),
        current_direct_camera_to_capture_accepted=True,
        user_reported_short_direct_observation_stable=True,
        fpga_native_display_stability_accepted=False,
        actual_camera_correction_accepted=False,
        all_camera_menu_values_independently_verified=False,
        camera_settings_checklist=observation["camera_checklist"],
        computer_use_paused_by_user=True,
        pending=pending,
    )
    status_path.write_text(json.dumps(status, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

prefix = """## 2026-10-11 当前同参数NV12直连稳定

经过b918全像素预览，在MJPEG与NV12下均持续闪烁；相机绕过FPGA，保持同一NV12/1920×1080/30fps配置且对准桌面或手，用户报告取景稳定、不闪烁。此对照将优先检查范围收窄至包含FPGA的链路（含HDMI-OUT线缆），仍未证实某个时序或代码根因。当前视频物理路线为相机直连采集卡，板上仍为b918。

用户要求完整相机设置说明，已依据佳能R50官方C011手册保存`docs/R50相机与OBS设置_20261011.md`，先核对所用NTSC/FHD59.94、固定HDMI1080p、相机＋监视器及关闭自动关机等设置。具体菜单未逐项现场核验，不把用户直连稳定继承成经过板子稳定。状态依据为`results/hardware_20261009/native_nv12_direct_stable_20261011.json`。高清连续显示和校正未验收，桌面控制仍停用；以下为历史阶段记录。

"""
for name in ["docs/继续工作.md", "README.md", "docs/高清预览联调_20261010.md"]:
    document = root / name
    before = document.read_text(encoding="utf-8-sig")
    if "## 2026-10-11 当前同参数NV12直连稳定" not in before:
        first, separator, rest = before.partition("\n")
        document.write_text(first + separator + "\n" + prefix + rest.lstrip("\n"), encoding="utf-8")
print("Saved stable same-format bypass result and official R50 checklist; FPGA native stability still fails.")
