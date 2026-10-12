"""Record the qualified, newly programmed DDR camera stage without acceptance claims."""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parents[1]
hardware = root / "results/hardware_20261009"
image = "release/ddr_camera_reconnect_20261011/video_correct_ddr_top.sbit"
qualification = json.loads((root / "release/ddr_camera_reconnect_20261011/build_qualification.json").read_text(encoding="utf-8-sig"))
assert qualification["simulations_passed"] and qualification["timing_passed"]
program = hardware / "program_ddr_camera_reconnect_20261011_123225.log"
text = program.read_text(encoding="utf-8-sig", errors="replace")
assert "COMMAND[Program] execute successfully" in text and "COMMAND[Verify] execute successfully" in text
assert not any(token in text for token in ["execute fail", "exec failed", "Fail to compare", "** Error"])
digest = hashlib.sha256((root / image).read_bytes()).hexdigest()
assert digest == qualification["files"]["video_correct_ddr_top.sbit"]
stamp = datetime.now(timezone.utc).isoformat()
pending = "User records about 30 seconds of four-marker camera target through the new DDR correction image; observe rectangular corrected result vs color bars/black, analyze real output before changing exposure or RTL thresholds. Desktop automation stays paused."
record = {
    "recorded_at_utc": stamp, "paused_by_user": False, "resumed_by_user": True,
    "current_image": image, "current_image_sha256": digest,
    "program_log": str(program.relative_to(root)), "program_verify_passed": True,
    "program_log_sha256": hashlib.sha256(program.read_bytes()).hexdigest(),
    "flash_modified": False,
    "source_sampling": [640, 480], "processed_output": [320, 452],
    "display": "1920x1080 nominal 60Hz; processed result 2x at x640,y88",
    "change": qualification["change"],
    "unrelated_compiled_sources_unchanged": qualification["unchanged_source_count"],
    "changed_control_regressions_passed": 3,
    "timing_passed_under_current_models": True,
    "previous_native_short_motion_evidence": "results/hardware_20261009/native_camera_resume_verified_20261011.json",
    "previous_native_test_duration_seconds": 27.9,
    "previous_native_decoded_frames": 836,
    "previous_native_black_like_frames": 0,
    "target_input_evidence": "results/hardware_20261009/native_target_input_20261011.json",
    "target_four_markers_visually_present": True,
    "host_video_default_threshold_valid_samples": 0,
    "host_threshold_limit": "Host NV12/H264 recording and OBS transform cannot prove actual in-board RGB values or corner coordinates",
    "actual_camera_correction_accepted": False,
    "actual_camera_display_accepted_for_current_image": False,
    "current_boot_ddr_bist_observed": False,
    "algorithm_update_fps_measured": False,
    "long_term_camera_display_verified": False,
    "computer_use_paused_by_user": True,
    "original_A_B_C_modified": False, "esc_behavior_modified": False,
    "stable_native_rollback": "release/camera_native_rx_first_20261010/camera_native_rx_first_top.sbit",
    "stable_native_rollback_entry": "下载高清相机预览_接收优先.cmd",
    "previous_ddr_release_retained": "release/ddr_startup_fixed_20261009",
    "pending": pending,
}
path = hardware / "ddr_camera_reconnect_state_20261011.json"
path.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
status_path = root / "docs/hardware_20261009.json"
status = json.loads(status_path.read_text(encoding="utf-8-sig"))
status.update(record,
    last_update_utc=stamp,
    current_temporary_image=image, current_temporary_image_sha256=digest,
    bitstream_sha256=digest,
    latest_camera_live_state=str(path.relative_to(root)),
    actual_camera_display_accepted=False,
    camera_capture_result="New full-DDR image Program/Verify passed; actual current output and camera correction awaiting manual target recording",
    obs_actual_format="1920x1080 NV12 30fps",
)
status_path.write_text(json.dumps(status, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
note = f"""# 相机校正接续记录（2026-10-11）

用户已恢复任务。1MHz扫描PG2L100H/00602899成功；b918原生RGB888预览重新下载并回读通过，用户核对FHD59.94和HDMI1080p。真实相机录像27.9秒、836帧没有整幅黑帧，669相邻帧对平均灰度差>1；已目视确认真实相机移动场景。只证明当前短时稳定，不解释此前闪烁，也不证明长时运行或实际HDMI帧率。

## 当前板上程序

将已验证的MS7200状态03重连修正移入完整DDR构建副本，只有这一条件变化；与旧DDR发布对比，其他107个编译源码完全相同。HDMI/DVI两次重连和启动开漏/NACK/缺器件检查通过，最终仿真0错误0警告。最初启动检查的重复测试模型警告已消除并重跑检查，不将那次带警告日志称作最终资格。

PDS全流程生成码流，`Design Summary : All Constraints Met`。当前发布`release/ddr_camera_reconnect_20261011`，sbit SHA256 `{digest}`，匹配smsk `{qualification['files']['video_correct_ddr_top.smsk']}`。新Program/Verify通过日志`{program.name}`，只写临时CRAM。当前板上已经是完整DDR/自动四色校正路径，旧85c DDR版和稳定b918原生预览均保留。

## 已收到的真实角标输入

用户录制`2026-10-11 12-09-34.mp4`，已原样归档。25秒帧确实看见红、绿、黄、蓝角标和测试纸，但OBS仍有放大裁边。按录像缩放后的RGB默认阈值分析，48个1fps抽样均不通过，25秒红/蓝计数0、绿80、黄40。这仅是主机端NV12/H264及OBS变换后的观察，不能代替实际板内RGB或断言相机设置错误。需要真正DDR输出核验，再决定曝光、阈值或其他修正。

## 待验证

已请用户在新完整校正版中录制约30秒的真实四角标目标，退出静态目标后查看居中矩形结果/彩条/黑屏。目的帧完整后发布，并在没有新有效帧时保留旧结果，符合原集成说明；因此退出目标后可能仍显示先前完整结果，不将这种保持状态称作持续实时更新。

当前启动DDR自检尚未独立观察，真实相机校正、更新帧率和长时运行仍未验收。后续确认真实阈值、固定/自动几何与缓慢移动结果，再记录实际吞吐。原始集成说明没有承诺任意1080p校正帧率；本工程源640×480、目的320×452、显示1080p固定扫描的含义分别记录。

状态为`results/hardware_20261009/ddr_camera_reconnect_state_20261011.json`。用户桌面控制暂停要求持续有效，继续由用户操作OBS/相机，CLI开发和数据分析正常进行。原A/B/C材料、静态图和Esc行为未修改。
"""
(root / "docs/相机校正接续_20261011.md").write_text(note, encoding="utf-8")
prefix = """## 2026-10-11 当前完整DDR校正副本已下载

b918高清真实运动短时检查通过后，将已验证的接收状态03重连修正移入完整DDR工程新副本；其他107个编译源码与旧DDR发布相同，三项控制回归和PDS时序通过。a4bd7...码流已Program/Verify成功，实际新日志`program_ddr_camera_reconnect_20261011_123225.log`。当前板上为`release/ddr_camera_reconnect_20261011`，不再是原生预览。

已保存真实四角标录像，主机转换后的红/蓝未达原阈值，不能据此冒充板内检测。等待新校正版30秒实拍录像和矩形/彩条/黑屏结果，当前真实校正及更新帧率未验收。详见`docs/相机校正接续_20261011.md`和`results/hardware_20261009/ddr_camera_reconnect_state_20261011.json`；桌面控制仍停用。以下为历史阶段记录。

"""
for name in ["docs/继续工作.md", "README.md", "docs/高清预览联调_20261010.md"]:
    document = root / name
    before = document.read_text(encoding="utf-8-sig")
    if "## 2026-10-11 当前完整DDR校正副本已下载" not in before:
        first, separator, rest = before.partition("\n")
        document.write_text(first + separator + "\n" + prefix + rest.lstrip("\n"), encoding="utf-8")
print("Recorded new qualified/programmed a4bd7 DDR image; real camera correction and throughput remain pending.")
