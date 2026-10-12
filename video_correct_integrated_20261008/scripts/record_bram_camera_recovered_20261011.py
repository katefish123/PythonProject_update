"""Archive actual camera source screenshots before the native preview comparison."""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import shutil
from PIL import Image

root = Path(__file__).resolve().parents[1]
hardware = root / "results/hardware_20261009"
videos = Path("C:/Users/夏菲/Videos")
observations = [
    ("direct_camera_before_reconnect_20261011.png", "Screenshot 2026-10-11 00-53-51.png", "R50 directly to capture"),
    ("bram_camera_recovered_before_native_20261011.png", "Screenshot 2026-10-11 00-57-02.png", "R50 through FPGA be1 BRAM preview to capture"),
]
evidence = []
for destination, original, route in observations:
    source = videos / original
    with Image.open(source) as frame:
        assert frame.size == (1920, 1080), (source, frame.size)
    target = hardware / destination
    shutil.copyfile(source, target)
    evidence.append({
        "original": str(source), "copy": str(target.relative_to(root)),
        "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
        "frame_size": [1920, 1080], "route_reported_by_user": route,
        "camera_photo_visually_verified": True,
    })

stamp = datetime.now(timezone.utc).isoformat()
pending = "Download qualified b918 RX-first full-pixel native preview with camera still live; then manually check image and source screenshot, preserving be1 rollback"
observation = {
    "recorded_at_utc": stamp,
    "user_report_verbatim": "真实取景但是非常糊",
    "programmed_image_before_comparison": "release/camera_live_bram_reconnect_20261010/camera_live_bram_top.sbit",
    "programmed_image_sha256": "be1a72cade3008e25cff3f6925bf6347fea8211da6e5447fdd82ef137e7f5212",
    "actual_camera_display_accepted": True,
    "continuous_camera_display_verified": False,
    "actual_camera_correction_accepted": False,
    "clarity_accepted": False,
    "bram_sampling": "320x180 RGB888, enlarged 6x6 to 1920x1080",
    "image_observation": "Both source PNGs contain actual photographed laptop/OBS screen; BRAM path has visibly coarse enlarged pixels compared with direct frame",
    "quality_metric_note": "Camera framing varies; this is a visual route comparison, not a controlled sharpness or resolution benchmark",
    "current_receiver_probe_decoded": False,
    "receiver_probe_note": "The live-camera screenshot does not contain the D104/B401 no-camera grid; do not decode photographed colors as status bits. Earlier no-input probe is historical.",
    "evidence": evidence,
    "programmed_image_changed": False,
    "obs_configuration_changed": False,
    "computer_use_paused_by_user": True,
    "pending": pending,
}
observation_path = hardware / "bram_camera_recovered_20261011.json"
observation_path.write_text(json.dumps(observation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
for relative in ["results/hardware_20261009/camera_flicker_state_20261011.json", "docs/hardware_20261009.json"]:
    path = root / relative
    status = json.loads(path.read_text(encoding="utf-8-sig"))
    status.update(
        last_update_utc=stamp,
        actual_camera_display_accepted=True,
        continuous_camera_display_verified=False,
        actual_camera_correction_accepted=False,
        clarity_accepted=False,
        current_receiver_probe_decoded=False,
        current_receiver_input_missing=False,
        previous_no_input_probe_is_historical=True,
        camera_recovered_evidence=str(observation_path.relative_to(root)),
        computer_use_paused_by_user=True,
        pending=pending,
    )
    path.write_text(json.dumps(status, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

prefix = """## 2026-10-11 当前FPGA低分辨率取景已恢复

相机接回FPGA后，用户报告真实取景但很糊。已读取并原样归档直连00:53:51和经过be1预览00:57:02的两个1920×1080源截图：均为真实拍摄的电脑/OBS画面，经过板子的6×6放大像素块明显，符合320×180 BRAM采样预览。两次构图并不完全相同，不能当作严格清晰度指标。实时运动依用户现场报告，连续稳定和校正未验收。

真实取景帧不显示D104/B401无输入状态格，不能从照片颜色解码板内状态；00:41的无输入诊断仅为历史。准备在相机保持取景时下载已资格通过的b918接收优先全像素版作对照，保留be1回退。原A/B/C材料及OBS参数保持，桌面控制仍停用。证据为`results/hardware_20261009/bram_camera_recovered_20261011.json`；以下为历史阶段记录。

"""
for name in ["docs/继续工作.md", "README.md", "docs/高清预览联调_20261010.md"]:
    path = root / name
    before = path.read_text(encoding="utf-8-sig")
    if "## 2026-10-11 当前FPGA低分辨率取景已恢复" not in before:
        first, separator, rest = before.partition("\n")
        path.write_text(first + separator + "\n" + prefix + rest.lstrip("\n"), encoding="utf-8")
print("Archived both actual source PNGs; be1 camera recovery recorded, native comparison pending.")
