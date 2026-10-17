"""Resume the task using new download and actual short camera-motion evidence."""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import shutil

root = Path(__file__).resolve().parents[1]
hardware = root / "results/hardware_20261009"
program = hardware / "program_camera_native_rx_first_20261011_115345.log"
scan = hardware / "scan_board_1mhz_20261011_115024.log"
program_text = program.read_text(encoding="utf-8-sig", errors="replace")
assert "COMMAND[Program] execute successfully" in program_text and "COMMAND[Verify] execute successfully" in program_text
assert not any(token in program_text for token in ["execute fail", "exec failed", "Fail to compare", "** Error"])
motion_path = hardware / "native_camera_motion_20261011.json"
motion = json.loads(motion_path.read_text(encoding="utf-8"))
assert motion["black_like_decoded_frames"] == 0
assert motion["successive_pairs_mean_difference_gt_1"] > 50
# The extracted peak frame was inspected: the camera pans from the laptop to a
# real desk/cup/cable scene, confirming physical motion rather than a static image.
motion["real_camera_motion_independently_visually_checked"] = True
motion["visual_observation"] = "Actual photographed laptop/desk/cup/cables; visible camera panning and motion blur in peak-change frame"
motion_path.write_text(json.dumps(motion, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
logs = root / "tools/obs-studio/portable/config/obs-studio/logs"
obs_log = max(logs.glob("*.txt"), key=lambda path: path.stat().st_mtime)
obs_copy = hardware / "obs_native_motion_resume_20261011.txt"
shutil.copyfile(obs_log, obs_copy)
stamp = datetime.now(timezone.utc).isoformat()
image = "release/camera_native_rx_first_20261010/camera_native_rx_first_top.sbit"
digest = hashlib.sha256((root / image).read_bytes()).hexdigest()
assert digest == "b918087a2ec5179e78f1a3f78e903538e401abbc120ba40201abb45a9fb5cbc2"
pending = "User records actual four-marker target with full OBS canvas; analyze markers, qualify isolated DDR reconnect build and then test real-camera perspective correction. Keep desktop automation paused."
record = {
    "recorded_at_utc": stamp, "paused_by_user": False, "resumed_by_user": True,
    "computer_use_paused_by_user": True,
    "current_image": image, "current_image_sha256": digest,
    "program_log": str(program.relative_to(root)), "program_verify_passed": True,
    "program_log_sha256": hashlib.sha256(program.read_bytes()).hexdigest(),
    "scan_log": str(scan.relative_to(root)),
    "flash_modified": False,
    "current_physical_video_route": "R50 -> FPGA HDMI-IN -> FPGA HDMI-OUT -> VC-002Pro -> USB PC, requested route confirmed by user observation",
    "camera_settings_user_confirmed_this_resume": {"movie_recording": "FHD 1920x1080 59.94fps", "HDMI_resolution": "1080p"},
    "obs_capture_format_verified": "1920x1080 NV12 30fps, buffering and hardware decoding disabled",
    "actual_camera_display_accepted": True,
    "short_native_camera_continuity_verified_seconds": motion["duration_container_seconds"],
    "short_native_camera_continuity_decoded_frames": motion["decoded_video_frames"],
    "short_native_camera_black_like_frames": 0,
    "real_camera_motion_visually_verified": True,
    "long_term_camera_display_verified": False,
    "actual_camera_correction_accepted": False,
    "earlier_flicker_root_cause_proven": False,
    "hardware_input_fps_measured": False,
    "algorithm_update_fps_measured": False,
    "motion_evidence": str(motion_path.relative_to(root)),
    "obs_log": str(obs_copy.relative_to(root)),
    "obs_canvas_initially_clipped": True,
    "obs_canvas_fit_requested_for_next_target_recording": True,
    "original_A_B_C_modified": False, "esc_behavior_modified": False,
    "pending": pending,
}
path = hardware / "native_camera_resume_verified_20261011.json"
path.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
for relative in ["docs/hardware_20261009.json", "results/hardware_20261009/camera_native_comparison_state_20261011.json", "results/hardware_20261009/camera_flicker_state_20261011.json"]:
    state_path = root / relative
    status = json.loads(state_path.read_text(encoding="utf-8-sig"))
    status.update(record,
        last_update_utc=stamp,
        current_temporary_image=image, current_temporary_image_sha256=digest,
        latest_native_program_log=str(program.relative_to(root)),
        latest_camera_live_state=str(path.relative_to(root)),
        physical_route_current=record["current_physical_video_route"],
        obs_actual_format=record["obs_capture_format_verified"],
        native_display_stability_accepted=True,
        fpga_native_display_stability_accepted=True,
        qualification_limit="Current short camera-motion observation only; prior flicker cause and long-term behavior unproven; real correction pending",
    )
    state_path.write_text(json.dumps(status, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
prefix = """## 2026-10-11 已恢复，高清真实运动短时验证通过

用户明确继续，采集卡与JTAG重新识别，1MHz扫描PG2L100H/00602899成功。新下载b918接收优先全像素版并Program/Verify通过，新日志`program_camera_native_rx_first_20261011_115345.log`。用户确认FHD59.94与HDMI1080p，并报告经过板子稳定取景。11:58:13源截图是真实相机画面；11:59:06录像已原样保存，解码27.9秒、836帧，无整幅黑帧，669相邻帧对平均灰度差>1；最大变化帧可见相机从电脑移向桌面杯子和线缆，真实运动已目视核验。这里只确认本次短时连续显示，不证明长时间稳定或解释昨晚闪烁。

当前板上仍b918，OBS NV12/1080p30，用户电脑界面控制继续停用。已请用户把OBS源Ctrl+F适配画布，再录全四角标静态测试图的真实相机输入；同时在新目录将已验证的接收重连修正合入完整DDR校正构建，原主源码及发布保留。实际校正和更新帧率尚未验收。当前状态为`results/hardware_20261009/native_camera_resume_verified_20261011.json`；以下为历史阶段记录。

"""
for name in ["docs/继续工作.md", "README.md", "docs/高清预览联调_20261010.md"]:
    document = root / name
    before = document.read_text(encoding="utf-8-sig")
    if "## 2026-10-11 已恢复，高清真实运动短时验证通过" not in before:
        first, separator, rest = before.partition("\n")
        document.write_text(first + separator + "\n" + prefix + rest.lstrip("\n"), encoding="utf-8")
print("Recorded new verified native image and actual 27.9-second motion evidence; task resumed, desktop automation stays paused.")
