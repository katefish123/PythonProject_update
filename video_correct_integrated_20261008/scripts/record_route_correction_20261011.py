"""Correct today's video qualification scope after the user identifies bypass wiring."""
from datetime import datetime, timezone
from pathlib import Path
import json
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
hardware = root / "results/hardware_20261009"
stamp = datetime.now(timezone.utc).isoformat()
quote = "刚刚没连过板子，现在重新连好了，现在有彩条"
correction = {
    "recorded_at_utc": stamp,
    "source": "Explicit physical-wiring clarification from user",
    "user_report_verbatim": quote,
    "earlier_inference_error": "Earlier route was inferred from a response about stable preview to a question describing FPGA wiring; physical route was not independently established",
    "corrected_scope_of_115906_motion_video": "R50 directly to capture; 27.9s and 836 frames with no black frames verify camera/capture only",
    "corrected_scope_of_120934_target_video": "R50 directly to capture; does not verify MS7200, source framebuffer or FPGA marker detection",
    "corrected_scope_of_125532_post_download_video": "R50 directly to capture; live camera image despite DDR download was caused by bypass route",
    "current_user_reported_route": "R50 -> FPGA HDMI-IN -> FPGA HDMI-OUT -> VC-002Pro -> USB PC",
    "current_fpga_user_result": "一直是彩条",
    "current_ddr_camera_correction_accepted": False,
    "today_fpga_native_continuity_accepted": False,
    "earlier_0100_bram_physical_evidence_invalidated": False,
    "earlier_build_simulation_program_evidence_invalidated": False,
    "computer_use_paused_by_user": True,
    "next": "Read genuine receiver diagnostic; distinguish missing HDMI input from DDR capture or marker rejection before further calibration",
}
correction_path = hardware / "route_scope_correction_20261011.json"
correction_path.write_text(json.dumps(correction, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

for relative in ["native_camera_motion_20261011.json", "native_target_input_20261011.json", "native_camera_resume_verified_20261011.json"]:
    path = hardware / relative
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if "current_physical_video_route" in value:
        value["previous_inferred_route"] = value["current_physical_video_route"]
        value["current_physical_video_route"] = "R50 directly to capture during the recorded test, user later clarified"
    if "source" in value:
        value["previous_inferred_source"] = value["source"]
        value["source"] = "Actual R50 direct-to-capture recording; FPGA bypassed"
    value.update(
        verification_scope_corrected_at_utc=stamp,
        source_route_corrected="R50 directly to capture; FPGA bypassed",
        correction_evidence=str(correction_path.relative_to(root)),
        actual_camera_display_accepted=False,
        fpga_path_qualified_by_this_record=False,
        direct_camera_capture_short_observation_valid=True,
    )
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

for relative in ["docs/hardware_20261009.json", "results/hardware_20261009/camera_native_comparison_state_20261011.json", "results/hardware_20261009/camera_flicker_state_20261011.json", "results/hardware_20261009/ddr_camera_reconnect_state_20261011.json"]:
    path = root / relative
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    value.update(
        last_update_utc=stamp,
        route_scope_correction=str(correction_path.relative_to(root)),
        current_physical_video_route=correction["current_user_reported_route"],
        physical_route_current=correction["current_user_reported_route"],
        previous_native_recording_was_bypass=True,
        fpga_native_display_stability_accepted=False,
        native_display_stability_accepted=False,
        actual_camera_display_accepted=False,
        actual_camera_correction_accepted=False,
        current_direct_camera_to_capture_accepted=True,
        current_fpga_video_observation="DDR a4bd7 after physical rewire: user reports continuous color bars",
        pending=correction["next"],
    )
    if "stable_native_rollback" in value:
        value["retained_native_candidate"] = value.pop("stable_native_rollback")
        value["retained_native_candidate_entry"] = value.pop("stable_native_rollback_entry")
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

ffmpeg = root / "tools/python_packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe"
videos = Path("C:/Users/夏菲/Videos")
for original_name, saved_stem in [
    ("2026-10-11 12-55-32.mp4", "camera_direct_after_ddr_download_20261011_125532"),
    ("2026-10-11 13-01-31.mp4", "ddr_fpga_colorbars_after_rewire_20261011_130131"),
]:
    source = videos / original_name
    if source.is_file():
        target = hardware / (saved_stem + ".mp4")
        shutil.copyfile(source, target)
        process = subprocess.run([str(ffmpeg), "-hide_banner", "-loglevel", "error", "-i", str(target), "-ss", "10", "-frames:v", "1", "-y", str(hardware / (saved_stem + ".png"))], capture_output=True, check=False)
        assert process.returncode == 0, process.stderr.decode("utf-8", errors="replace")

note = """## 接线路径核实后的重要更正

用户明确“刚刚没连过板子，现在重新连好了，现在有彩条”。因此今天11:59:06的27.9秒运动录像、12:09:34的角标录像和12:55:32新DDR下载后的实时画面，均来自相机直连采集卡，不能证明FPGA原生预览、DDR源采集或板内角标检测通过。此前以问题中给出的接线加“取景稳定”回答推断物理路线，是助手判断不充分；当前资格已撤回并明确更正。真实录像本身仍证明相机和采集卡能稳定出图，构建/仿真/下载证据以及更早明确经过be1的粗预览证据不受此次更正影响。

现在用户已实际接回FPGA，a4bd7完整DDR程序输出一直彩条。仅能确认当前发送输出正常，不能从彩条判断是输入未恢复、DDR采集还是角标识别失败。先切到保留的be1接收诊断读取真实状态，再继续。更正依据为`results/hardware_20261009/route_scope_correction_20261011.json`。

"""
document = root / "docs/相机校正接续_20261011.md"
before = document.read_text(encoding="utf-8-sig")
if "## 接线路径核实后的重要更正" not in before:
    first, separator, rest = before.partition("\n")
    document.write_text(first + separator + "\n" + note + rest.lstrip("\n"), encoding="utf-8")
prefix = "## 2026-10-11 已更正直连录像的验证范围\n\n" + note.split("\n\n", 1)[1]
for name in ["README.md", "docs/继续工作.md", "docs/高清预览联调_20261010.md"]:
    path = root / name
    before = path.read_text(encoding="utf-8-sig")
    if "## 2026-10-11 已更正直连录像的验证范围" not in before:
        first, separator, rest = before.partition("\n")
        path.write_text(first + separator + "\n" + prefix + rest.lstrip("\n"), encoding="utf-8")
print("Corrected qualification scope: today's motion/target recordings were direct-camera capture; real FPGA DDR route remains color bars and unaccepted.")
