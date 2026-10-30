"""Keep current entry consistent after the verified-baseline recovery download."""
from pathlib import Path
import json

R=Path(__file__).resolve().parents[1]
hw=R/"results/hardware_20261009"
path=hw/"clean_camera_state_20261011.json"
state=json.loads(path.read_text(encoding="utf-8-sig"))
assert state["current_image_sha256"]=="a4bd7f42732c100b598cb974e03477877aab4032e39f6de558bb245d666e232e"
assert state["program_log"].endswith("program_ddr_camera_reconnect_20261011_235140.log")
state.update(phase="Restore verified baseline HDMI output after capture HDMI unplug",
    download_entry="下载相机校正_重连版.cmd",diagnostic_signature=None,diagnostic_fields=None,
    previous_verified_baseline="results/hardware_20261009/working_clean_baseline_verified_20261011.json",
    previous_verified_scope="Historical clean a4 image physically showed a complete corrected page; 18:12:18 recording retained about47s after first page without fallback/blackout. Current boot/output still pending.",
    capture_hdmi_recovery_evidence="results/hardware_20261009/capture_hdmi_recovery_latest_20261011.json",
    physical_route_current="Camera directly connected to capture card for isolation; FPGA reconnection pending user's action.",
    current_failed_stage=None,clarity_accepted=False,clarity_improvement_accepted=False,
    pending="Reconnect camera -> FPGA IN and FPGA OUT -> capture, KEY0 once, manually reactivate OBS; first check for HDMI colorbars/image before asking for a target recording.")
path.write_text(json.dumps(state,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
main_path=R/"docs/hardware_20261009.json"
main=json.loads(main_path.read_text(encoding="utf-8-sig"))
main.update(state,capture_result="After HDMI unplug, camera direct capture is normal; verified baseline a4 reprogrammed and readback passed, awaiting FPGA output route test. Direct camera image is not FPGA evidence.")
main_path.write_text(json.dumps(main,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
guide='''# 当前工程入口

当前板上已恢复**实测过的基础校正版a4**，新Program/Verify通过，先恢复HDMI输出，再继续高清升级。基础版640×480源、320×452结果，放大2倍显示于1080p的640×904窗口。当前启动后的图像恢复仍待确认，不能把历史验收用于这次启动。

用户报告拔过采集卡HDMI，板子没断电；系统识别VC-002Pro正常，插牢/KEY0/重新激活OBS后仍无视频信号。随后相机直连采集卡恢复真实取景，因此当前缺信号发生在经过FPGA的输出路线，输出线与诊断版启动尚未完全区分。直连取景只证明相机和采集卡通路正常。

| 用途 | 文件 |
| --- | --- |
| 当前PDS基础工程 | `diagnostics/ddr_camera_reconnect_20261011/results/video_correct_ddr_reconnect.pds` |
| 当前下载入口 | `下载相机校正_重连版.cmd` |
| 当前码流与源码闭包 | `release/ddr_camera_reconnect_20261011` |
| 本次下载回读 | `results/hardware_20261009/program_ddr_camera_reconnect_20261011_235140.log` |
| 当前状态 | `results/hardware_20261009/clean_camera_state_20261011.json` |
| 基础版历史实测 | `results/hardware_20261009/working_clean_baseline_verified_20261011.json` |
| 本次HDMI拔插/直连对照 | `results/hardware_20261009/capture_hdmi_recovery_latest_20261011.json` |
| 保留的高清D206诊断工程 | `release/ddr_camera_hires_status_20261011`、`下载高清校正诊断.cmd` |
| 高清缺图证据与后续计划 | `docs/高清显示排查_20261011.md` |

基础码流SHA256为`a4bd7f42732c100b598cb974e03477877aab4032e39f6de558bb245d666e232e`，本次235140日志Program/Verify通过。原先18:12:18实录显示完整矩形校正图，并保留约47秒短时稳定证据；该证据是历史验证。

现在先接回：相机 → 板子HDMI-IN；板子HDMI-OUT → 采集卡HDMI入口；采集卡USB保持接电脑。接好后按住KEY0约1秒再松开，等10秒，OBS取消激活/等2秒/激活。先确认有彩条或图像，不必先打开测试图。

高清正常版实录只显示校正窗口顶边细线，未验收完整高清图。D206源960×540/结果640×904诊断的八项仿真、解码器、最终时序和下载通过，但真实诊断录像未取得，后续发生无视频信号。它已保留，不等于确认该码流导致了拔插故障。

连续读取/缓存修复副本位于`diagnostics/ddr_hires_read_ahead_20261011`，两项单元检查通过，未完成整屏/时序资格，未上板。待输出恢复后继续确认高清逐行读取问题并资格验证。

原A/B/C、旧发布、原测试图和Esc行为保留，桌面控制停用。只写临时CRAM，未写Flash，断电后重新下载。历史文档中的“当前”属于当时阶段，以本入口和`docs/hardware_20261009.json`为准。
'''
(R/"docs/当前工程入口_20261011.md").write_text(guide,encoding="utf-8")
prefix='''## 2026-10-11 23:52 最新：先恢复基础a4的HDMI输出

采集卡HDMI拔插后用户报告无视频信号；USB设备仍正常识别，板子已配置，重插/KEY0/刷新OBS未恢复。相机直连采集卡能显示真实取景，尚不能区分板子输出线和D206启动问题。当前已重新下载保留的实测基础a4版并回读通过，日志`program_ddr_camera_reconnect_20261011_235140.log`。等待用户接回板子、KEY0一次并重新激活OBS，先看是否有彩条/图像。

当前状态`results/hardware_20261009/clean_camera_state_20261011.json`，最新入口`docs/当前工程入口_20261011.md`，直连对照和前后状态备份为`results/hardware_20261009/capture_hdmi_recovery_latest_20261011.json`。直连相机画面不能作为FPGA恢复证据。高清正常版缺行、D206码流与源码、连续读取未上板副本均保留；原资料未改，未写Flash。以下为历史阶段记录。

'''
for relative in ["README.md","docs/继续工作.md","docs/相机校正接续_20261011.md"]:
    p=R/relative
    old=p.read_text(encoding="utf-8-sig")
    if "23:52 最新：先恢复基础a4的HDMI输出" not in old:p.write_text(prefix+old,encoding="utf-8")
print("Saved verified baseline restore, current direct-camera scope and pending output reconnection.")
