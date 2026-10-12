"""Create a verified local pause snapshot without hardware or desktop actions."""
from datetime import datetime, timedelta, timezone
from pathlib import Path
import hashlib
import json
import shutil
import zipfile

root = Path(__file__).resolve().parents[1]
assert root.resolve() == Path("C:/D/FPGA/video_correct_integrated_20261008").resolve()
hardware = root / "results/hardware_20261009"
now = datetime.now(timezone.utc)
local = now.astimezone(timezone(timedelta(hours=8)))
stamp = local.strftime("%Y%m%d_%H%M%S")
snapshot = root / "release" / ("hdmi_preview_paused_" + stamp)
snapshot.mkdir(parents=True, exist_ok=False)

def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

current_image = root / "release/camera_native_rx_first_20261010/camera_native_rx_first_top.sbit"
current_digest = sha(current_image)
assert current_digest == "b918087a2ec5179e78f1a3f78e903538e401abbc120ba40201abb45a9fb5cbc2"
program_log = hardware / "program_camera_native_rx_first_20261011_005851.log"
program_text = program_log.read_text(encoding="utf-8-sig", errors="replace")
assert "COMMAND[Program] execute successfully" in program_text
assert "COMMAND[Verify] execute successfully" in program_text
assert not any(token in program_text for token in ["execute fail", "exec failed", "Fail to compare", "** Error"])

scene_path = root / "tools/obs-studio/portable/config/obs-studio/basic/scenes/FPGA.json"
scene = json.loads(scene_path.read_text(encoding="utf-8-sig"))
source = next(item for item in scene["sources"] if item.get("id") == "dshow_input")
settings = source["settings"]
assert settings["resolution"] == "1920x1080"
assert settings["frame_interval"] == 333333
assert settings["video_format"] == 201
obs_format = "1920x1080 NV12 30fps, buffering and hardware decoding disabled"
pending = "Paused by user. Resume only after explicit user continuation: verify R50 checklist and saved direct-capture baseline, then inspect native FPGA clock/sync/IO and HDMI-OUT path. Keep desktop automation paused unless user resumes it. Re-download qualified image after board power loss; do not inherit old hardware acceptance."
pause_record = {
    "recorded_at_utc": now.isoformat(),
    "recorded_at_local": local.isoformat(),
    "paused_by_user": True,
    "automatic_resume_created": False,
    "computer_use_paused_by_user": True,
    "project_root": str(root),
    "snapshot_directory": str(snapshot.relative_to(root)),
    "current_last_programmed_image": str(current_image.relative_to(root)),
    "current_last_programmed_sha256": current_digest,
    "program_verify_passed": True,
    "latest_program_log": str(program_log.relative_to(root)),
    "latest_program_log_sha256": sha(program_log),
    "flash_modified": False,
    "power_loss_requires_reprogramming": True,
    "current_physical_video_route_reported": "R50 directly to VC-002Pro capture; USB to PC; FPGA bypassed",
    "obs_capture_settings_persisted": settings,
    "obs_capture_format": obs_format,
    "direct_camera_to_capture_user_result": "取景稳定，不闪烁",
    "direct_observation_seconds_requested": 20,
    "direct_long_term_stability_verified": False,
    "fpga_bram_camera_observed": True,
    "fpga_bram_camera_quality": "320x180 samples enlarged 6x6; visibly coarse",
    "fpga_native_real_camera_observed": True,
    "fpga_native_stability_accepted": False,
    "fpga_native_result": "Real camera frame present, continuous flicker with both MJPEG and NV12",
    "actual_camera_correction_accepted": False,
    "all_camera_menu_values_independently_verified": False,
    "camera_settings_checklist": "docs/R50相机与OBS设置_20261011.md",
    "hardware_measurements_note": "Older RX/DDR/temperature fields are historical observations, not current readings or proof of live-camera acceptance.",
    "pending": pending,
    "original_A_B_C_modified": False,
    "esc_behavior_modified": False,
    "no_subagents_running_checked": True,
}
pause_path = hardware / "paused_state_20261011.json"
pause_path.write_text(json.dumps(pause_record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

for relative in ["docs/hardware_20261009.json", "results/hardware_20261009/camera_native_comparison_state_20261011.json", "results/hardware_20261009/camera_flicker_state_20261011.json"]:
    path = root / relative
    status = json.loads(path.read_text(encoding="utf-8-sig"))
    if "physical_route_current" in status:
        status["physical_route_before_latest_bypass"] = status["physical_route_current"]
    if "capture_mode" in status:
        status["previous_web_preview_capture_mode"] = status["capture_mode"]
    status.update(
        last_update_utc=now.isoformat(),
        paused_by_user=True,
        resumed_by_user=False,
        paused_at_local=local.isoformat(),
        latest_pause_state=str(pause_path.relative_to(root)),
        pause_snapshot=str(snapshot.relative_to(root)),
        current_physical_video_route=pause_record["current_physical_video_route_reported"],
        physical_route_current=pause_record["current_physical_video_route_reported"],
        obs_actual_format=obs_format,
        capture_mode=obs_format,
        obs_capture_format_verified=obs_format,
        current_temporary_image=str(current_image.relative_to(root)),
        current_temporary_image_sha256=current_digest,
        latest_native_program_log=str(program_log.relative_to(root)),
        program_log_sha256=sha(program_log),
        current_direct_camera_to_capture_accepted=True,
        fpga_native_display_stability_accepted=False,
        actual_camera_correction_accepted=False,
        computer_use_paused_by_user=True,
        automatic_resume_created=False,
        pending=pending,
    )
    path.write_text(json.dumps(status, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

note = f"""# 暂停与接续说明（2026-10-11）

用户要求保存后暂停，记录时间为{local.strftime('%Y-%m-%d %H:%M:%S')}（北京时间）。工程位于`{root}`，当前暂停快照为`{snapshot.relative_to(root)}`，另有同名ZIP及SHA256清单。停止工程推进，不创建明天自动运行或提醒；等用户明确继续。

## 当前真实结果

- 相机R50直接接VC-002Pro，在OBS NV12、1920×1080、30fps下，用户进行约20秒对照后报告取景稳定、不闪烁。这是短时现场观察，未验收长时间稳定。
- 经be1双BRAM诊断曾恢复真实取景，源截图已保存；它以320×180采样并放大6×6，画质粗糙。
- 经b918接收优先全RGB888版已看到真实相机帧，清晰细节恢复，但持续闪烁；MJPEG和NV12均不稳定。不能把单张高清帧称作连续显示通过。
- 01:00—01:07:04的OBS日志有554次EOI缺失及70次解码失败；NV12已在01:07:15确认生效，01:07:27截图为全黑帧。错误日志是症状，尚未证明具体根因。
- 实际相机透视校正、更新帧率及长时间运行仍未验收。此前DDR自检和内部fixture的验证为历史独立检查，不能替代真实相机验收。

## 当前文件与接线

最后实际下载的板内程序是`release/camera_native_rx_first_20261010/camera_native_rx_first_top.sbit`，SHA256 `{current_digest}`。本次新下载和回读均通过，日志`results/hardware_20261009/{program_log.name}`。只写临时CRAM，未写Flash/eFuse。断电后该程序会丢失，下次先按实际板卡状态重新下载；不得沿用旧回读日志冒充新下载成功。

当前用户确认的视频接线是相机直接接采集卡、USB接电脑，绕过FPGA。OBS仍只有实际采集源，当前保存配置为NV12、1920×1080、30fps。相机FHD59.94、NTSC、HDMI固定1080p、相机＋监视器和关闭自动关机等完整核对表位于[相机设置](R50相机与OBS设置_20261011.md)；用户尚未逐项反馈核对结果。

保留恢复入口`恢复相机预览_重连修正版.cmd`（be1）及`恢复相机预览.cmd`（00f3）；高清下载入口`下载高清相机预览_接收优先.cmd`（b918）和发送优先高清版本（00e6）；主DDR校正发布为`release/ddr_startup_fixed_20261009`（85c1）。全部既有源码、码流和原始材料保持，Esc停止控制/关闭静态图的行为未修改。

## 下次接续顺序

1. 用户明确恢复后，先确认板卡电源、USB/JTAG、采集卡和R50取景，核对相机设置及当前直连稳定基线。电脑桌面控制仍按用户之前“暂时不用computeruse”的要求停用，直到用户恢复该功能。
2. 若板子断过电，按将要测试的资格通过版本重新下载并完成新回读，保留实际日志；当前高清版仍是失败候选，不作为最终验收程序。
3. 保持相机/OBS同参数，对照经过FPGA与直连，优先检查HDMI-OUT连接、接收/发送同步、实际输出时钟和外部IO时序。避免反复盲目改相机菜单或复位。
4. 取得可连续运行的真实预览和运动证据后，再进行四色角标真实拍摄、DDR透视校正与实际更新速率验证。没有对应实体证据时继续保留“未验收”。

状态索引为`results/hardware_20261009/paused_state_20261011.json`。不要重跑硬编码早期码流、早期日志的记录脚本覆盖本次暂停状态。
"""
(root / "docs/暂停记录_20261011.md").write_text(note, encoding="utf-8")
prefix = f"""## 2026-10-11 已保存并暂停

用户要求保存，当前停止工程推进，等明确继续。接续说明为[暂停记录](docs/暂停记录_20261011.md)，快照为`{snapshot.relative_to(root)}`及同名ZIP。最后下载b918、Program/Verify通过；实际接线已改为相机直连采集卡，NV12/1080p30直连稳定，经过FPGA高清版仍闪烁，校正未验收。断电后需新下载和回读。桌面控制仍停用，不自动恢复。以下为历史阶段记录。

"""
for name in ["docs/继续工作.md", "README.md", "docs/高清预览联调_20261010.md"]:
    path = root / name
    before = path.read_text(encoding="utf-8-sig")
    first, separator, rest = before.partition("\n")
    this_prefix = prefix if name == "README.md" else prefix.replace("(docs/暂停记录_20261011.md)", "(暂停记录_20261011.md)")
    path.write_text(first + separator + "\n" + this_prefix + rest.lstrip("\n"), encoding="utf-8")

def copy_relative(path):
    relative = path.relative_to(root)
    target = snapshot / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, target)

extensions = {".v", ".vh", ".sv", ".svh", ".fdc", ".sdc", ".pdc", ".py", ".ps1", ".cmd", ".tcl", ".ini", ".json", ".md", ".txt", ".hex", ".mem", ".mif", ".coe", ".csv", ".xml", ".pds", ".pdsproj", ".png", ".jpg", ".jpeg", ".bin", ".do"}
for directory in ["rtl", "constr", "sim", "pds", "scripts", "docs", "vendor"]:
    base = root / directory
    for path in base.rglob("*"):
        if path.is_file() and path.suffix.lower() in extensions and not any(part in {".git", "__pycache__", "work"} for part in path.relative_to(base).parts):
            copy_relative(path)
for path in root.iterdir():
    if path.is_file() and (path.suffix.lower() == ".cmd" or path.name in {"README.md", "modelsim.ini"}):
        copy_relative(path)
for directory in ["camera_native_rx_first_20261010", "camera_live_native_20261010", "camera_live_bram_reconnect_20261010", "camera_live_bram_20261010", "ddr_startup_fixed_20261009"]:
    release = root / "release" / directory
    for path in release.rglob("*"):
        if path.is_file():
            copy_relative(path)
evidence_extensions = {".json", ".png", ".jpg", ".jpeg", ".log", ".txt", ".csv", ".mp4", ".nv12", ".npz"}
for path in hardware.iterdir():
    if path.is_file() and path.suffix.lower() in evidence_extensions:
        copy_relative(path)
copy_relative(scene_path)
obs_log = root / "tools/obs-studio/portable/config/obs-studio/logs/2026-10-10 19-51-31.txt"
copy_relative(obs_log)
(snapshot / "PAUSE_README.md").write_text(note, encoding="utf-8")

files = sorted(path for path in snapshot.rglob("*") if path.is_file())
manifest = {str(path.relative_to(snapshot)).replace("\\", "/"): {"bytes": path.stat().st_size, "sha256": sha(path)} for path in files}
manifest_path = snapshot / "manifest_sha256.json"
manifest_path.write_text(json.dumps({"recorded_at_utc": now.isoformat(), "files": manifest}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
for relative, expected in manifest.items():
    path = snapshot / relative
    assert path.stat().st_size == expected["bytes"] and sha(path) == expected["sha256"], relative

archive = snapshot.with_suffix(".zip")
with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=1) as bundle:
    for path in sorted(path for path in snapshot.rglob("*") if path.is_file()):
        bundle.write(path, str(path.relative_to(snapshot)))
with zipfile.ZipFile(archive) as bundle:
    assert bundle.testzip() is None
archive_digest = sha(archive)
archive.with_suffix(".zip.sha256").write_text(archive_digest + "  " + archive.name + "\n", encoding="utf-8")
verification = {
    "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
    "snapshot_directory": str(snapshot), "archive": str(archive),
    "archive_sha256": archive_digest, "snapshot_files_hashed": len(manifest),
    "copied_file_hashes_verified": True, "archive_crc_verified": True,
    "paused_by_user": True, "automatic_resume_created": False,
}
(hardware / "pause_snapshot_verification_20261011.json").write_text(json.dumps(verification, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(verification, ensure_ascii=False, indent=2))
