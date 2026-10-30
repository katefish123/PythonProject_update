"""Record actual FPGA-route unplug/reconnect video with explicit measurement limits."""
from datetime import datetime, timezone
from pathlib import Path
import json

root = Path(__file__).resolve().parents[1]
stamp = datetime.now(timezone.utc).isoformat()
evidence = "results/hardware_20261009/bram_diagnostic_fpga_20261011.json"
data = json.loads((root / evidence).read_text(encoding="utf-8-sig"))
assert data["decoded_grid_samples"] == 17
state_path = root / "results/hardware_20261009/receiver_diagnostic_after_rewire_20261011.json"
state = json.loads(state_path.read_text(encoding="utf-8-sig"))
assert state["current_image_sha256"] == data["image"]
pending = "Build independent status-overlay diagnostic to read width/height/sync while camera is live. Keep retained be1 and all full-DDR releases; no desktop automation."
state.update(
    updated_at_utc=stamp,
    user_report_verbatim=data["user_verbatim"],
    actual_coarse_camera_video_evidence=evidence,
    coarse_camera_video_visually_checked=True,
    camera_input_unplug_and_recovery_visually_checked=True,
    current_receiver_probe_decoded=True,
    receiver_probe_decoded_scope="D104/B401 diagnostic in 17 one-second samples during input unplug. Width=30039, height=0, period=43028 are not a valid live camera timing measurement.",
    current_valid_camera_width_height_measured=False,
    obs_canvas_fit_confirmed=True,
    pending=pending,
)
state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
status_path = root / "docs/hardware_20261009.json"
status = json.loads(status_path.read_text(encoding="utf-8-sig"))
status.update(last_update_utc=stamp,
    actual_coarse_camera_video_evidence=evidence,
    current_receiver_probe_decoded=True,
    receiver_probe_decoded_scope=state["receiver_probe_decoded_scope"],
    current_valid_camera_width_height_measured=False,
    obs_canvas_fit_confirmed=True,
    capture_result="13:39:57 actual FPGA-route video shows real coarse camera, unplug diagnostic grid, and camera recovery. Native clarity/full DDR correction unaccepted.",
    pending=pending)
status_path.write_text(json.dumps(status, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
prefix = """## 2026-10-11 真实粗预览与断线恢复已取证

当前保留be1粗预览，13:39:57录像由用户核实的“R50 → FPGA HDMI-IN → FPGA HDMI-OUT → 采集卡”链路生成，录像中真实取景移动、拔线后红绿状态格及插回后的取景恢复均已目视核验。OBS画布已适配为1920×1080。

已读到17个D104/B401状态样本，但均处于相机线拔下的时段，宽30039、高0、行周期43028不能当作正常相机时序。下一步在独立副本增加持续可见的状态格，只改输出诊断显示，保留接收、缓存和配置逻辑，并经仿真、时序、下载校验后读取接线正常时的实际状态。高清预览、完整DDR校正及实际更新帧率仍未验收；电脑界面控制仍停用。

证据为`results/hardware_20261009/bram_diagnostic_fpga_20261011.json`；此前11:59/12:09/12:55录像均是直连相机，资格更正保留。下文为历史记录。

"""
for name in ["README.md", "docs/继续工作.md", "docs/相机校正接续_20261011.md"]:
    path = root / name
    before = path.read_text(encoding="utf-8-sig")
    if "## 2026-10-11 真实粗预览与断线恢复已取证" not in before:
        first, separator, rest = before.partition("\n")
        path.write_text(first + separator + "\n" + prefix + rest.lstrip("\n"), encoding="utf-8")
print("Recorded real coarse FPGA video and disconnection/recovery; invalid unplug timing not accepted.")
