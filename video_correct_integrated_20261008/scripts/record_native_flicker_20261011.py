"""Record actual unstable native video and the verified NV12 comparison."""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import shutil
from PIL import Image

root = Path(__file__).resolve().parents[1]
hardware = root / "results/hardware_20261009"
videos = Path("C:/Users/夏菲/Videos")
evidence = []
for original, name, label in [
    ("Screenshot 2026-10-11 01-02-08.png", "native_camera_mjpeg_flicker_20261011.png", "Native b918, MJPEG 1080p30"),
    ("Screenshot 2026-10-11 01-07-27.png", "native_camera_nv12_black_frame_20261011.png", "Native b918, NV12 1080p30"),
]:
    source = videos / original
    target = hardware / name
    shutil.copyfile(source, target)
    with Image.open(target) as image:
        assert image.size == (1920, 1080)
        extrema = image.convert("RGB").getextrema()
    evidence.append({
        "original": str(source), "copy": str(target.relative_to(root)), "label": label,
        "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
        "rgb_extrema": extrema,
        "all_black": all(high == 0 for low, high in extrema),
    })
log_source = root / "tools/obs-studio/portable/config/obs-studio/logs/2026-10-10 19-51-31.txt"
log_copy = hardware / "obs_native_mjpeg_and_nv12_flicker_20261011.txt"
shutil.copyfile(log_source, log_copy)
text = log_copy.read_text(encoding="utf-8-sig", errors="replace")
assert "01:07:15.440: \tformat: NV12" in text
native_lines = [line for line in text.splitlines() if line[:8] >= "01:00:00" and line[:8] < "01:07:04"]
counts = {
    "sample_start": "2026-10-11 01:00:00 Asia/Shanghai",
    "sample_end_exclusive": "2026-10-11 01:07:04 Asia/Shanghai",
    "eoi_missing_warnings": sum("EOI missing" in line for line in native_lines),
    "decode_errors": sum("Error decoding video" in line for line in native_lines),
    "note": "OBS diagnostics only; not a count of complete displayed frames or actual hardware VS edges",
}
stamp = datetime.now(timezone.utc).isoformat()
pending = "User compares direct camera-to-capture with identical NV12 1080p30 settings, camera aimed at desk or hand instead of computer screen, observes 20 seconds; desktop automation stays paused"
observation = {
    "recorded_at_utc": stamp,
    "current_image": "release/camera_native_rx_first_20261010/camera_native_rx_first_top.sbit",
    "program_log": "results/hardware_20261009/program_camera_native_rx_first_20261011_005851.log",
    "native_user_report_verbatim": "有真是取景，但是一直在闪烁，非常不稳定",
    "native_real_camera_observed": True,
    "native_real_camera_source_frame_verified": True,
    "native_display_stability_accepted": False,
    "nv12_user_result_verbatim": "仍然闪烁",
    "nv12_settings_verified_in_obs_log": True,
    "nv12_settings": "1920x1080, 30fps, NV12; same 39ae5db8 capture device",
    "nv12_saved_source_frame_all_black": evidence[1]["all_black"],
    "evidence": evidence,
    "obs_log": str(log_copy.relative_to(root)),
    "mjpeg_log_counts": counts,
    "root_cause_proven": False,
    "actual_camera_display_accepted": False,
    "clarity_accepted": False,
    "continuous_camera_display_verified": False,
    "actual_camera_correction_accepted": False,
    "computer_use_paused_by_user": True,
    "programmed_image_changed_after_native_download": False,
    "pending": pending,
}
path = hardware / "camera_native_flicker_observation_20261011.json"
path.write_text(json.dumps(observation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
for relative in ["results/hardware_20261009/camera_native_comparison_state_20261011.json", "results/hardware_20261009/camera_flicker_state_20261011.json", "docs/hardware_20261009.json"]:
    status_path = root / relative
    status = json.loads(status_path.read_text(encoding="utf-8-sig"))
    status.update(
        last_update_utc=stamp,
        native_real_camera_observed=True,
        native_display_stability_accepted=False,
        native_user_report_verbatim=observation["native_user_report_verbatim"],
        nv12_user_result=observation["nv12_user_result_verbatim"],
        obs_capture_format_verified=observation["nv12_settings"],
        actual_camera_display_accepted=False,
        clarity_accepted=False,
        continuous_camera_display_verified=False,
        actual_camera_correction_accepted=False,
        latest_native_flicker_evidence=str(path.relative_to(root)),
        computer_use_paused_by_user=True,
        capture_result="Native camera photo verified but user reports continuous flicker; NV12 1080p30 also flickers and source PNG is all black",
        pending=pending,
    )
    status_path.write_text(json.dumps(status, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

prefix = """## 2026-10-11 当前高清取景出现但持续闪烁

b918新下载后，用户报告真实取景但一直闪烁，非常不稳定。01:02:08源PNG确实包含真实相机画面，细节较be1放大预览明显，但单帧不能证明连续稳定。OBS在此阶段连续记录MJPEG EOI缺失与解码失败。用户只改格式至NV12，日志01:07:15确认1920×1080/30fps/NV12与同一采集设备生效，仍报告闪烁；01:07:27源PNG是全黑帧。NV12结果不能单凭这一帧分清HDMI失锁、USB/格式传输或光学屏幕闪动，也不能仅以MJPEG错误断言板内时序是根因。

下一步保持NV12/1080p30，以相机直连采集卡且对准桌面或手的20秒观察作对照。板上仍为b918，不额外复位或下载；be1恢复入口保留，桌面控制停用。状态与原样图/日志为`results/hardware_20261009/camera_native_flicker_observation_20261011.json`。高清连续画面和校正未验收；以下为历史阶段记录。

"""
for name in ["docs/继续工作.md", "README.md", "docs/高清预览联调_20261010.md"]:
    document = root / name
    before = document.read_text(encoding="utf-8-sig")
    if "## 2026-10-11 当前高清取景出现但持续闪烁" not in before:
        first, separator, rest = before.partition("\n")
        document.write_text(first + separator + "\n" + prefix + rest.lstrip("\n"), encoding="utf-8")
print(json.dumps(counts, ensure_ascii=False))
print("Saved real native photo, all-black NV12 frame and log; stability not accepted.")
