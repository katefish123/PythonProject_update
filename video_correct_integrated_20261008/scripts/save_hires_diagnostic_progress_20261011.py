"""Save the current board entry, real failure evidence and the unprogrammed fix prototype."""
from pathlib import Path
import json

R=Path(__file__).resolve().parents[1]
state=json.loads((R/"results/hardware_20261009/hires_status_state_20261011.json").read_text(encoding="utf-8-sig"))
assert state["current_image_sha256"]=="614f6814fe9dad63359176d9cb43a3b4273cf621c7247a3c15e2cafdbde997d7" and state["program_verify_passed"]
unit=json.loads((R/"diagnostics/ddr_hires_read_ahead_20261011/results/unit_qualification.json").read_text(encoding="utf-8-sig"))
assert unit["unit_checks_passed"] and not unit["qualified_for_board"] and not unit["programmed"]
guide='''# 当前工程入口

当前最后一次下载为 **高清显示诊断D206版**，Program/Verify通过。它保持960×540源采样、640×904校正结果和1080p输出，底部暂时显示红绿诊断格。高清正常版的实录只显示顶边细线，完整高清图及清晰度提升尚未验收；原来已实测的完整基础校正版保留。

| 用途 | 文件 |
| --- | --- |
| 当前PDS诊断工程 | `diagnostics/ddr_camera_hires_status_20261011/results/ddr_camera_hires_status.pds` |
| 当前下载入口 | `下载高清校正诊断.cmd` |
| 当前码流、检查记录及源码快照 | `release/ddr_camera_hires_status_20261011` |
| 当前下载校验 | `results/hardware_20261009/program_ddr_camera_hires_status_20261011_215211.log` |
| 当前板上状态记录 | `results/hardware_20261009/hires_status_state_20261011.json` |
| 高清缺图实录及分析 | `results/hardware_20261009/hires_display_failure_20261011_211430.json` |
| 恢复已实测基础校正版 | `下载相机校正_重连版.cmd` |
| 基础版本实测证据 | `results/hardware_20261009/working_clean_baseline_verified_20261011.json` |
| 静态大角标测试图 | `显示相机测试图_大角标.cmd` |
| 原有静态测试图 | `显示相机测试图.cmd` |
| OBS查看输出 | `打开OBS.cmd` |

当前码流SHA256为 `614f6814fe9dad63359176d9cb43a3b4273cf621c7247a3c15e2cafdbde997d7`。八项仿真、D206解码器字段检查、最终PDS时序及Program/Verify通过。第一次布局的1ps保持时间违例已拒绝、留档并修复，未下载该失败码流，未放宽时序约束。

接线保持：R50 → FPGA HDMI-IN；FPGA HDMI-OUT → VC-002Pro采集卡 → 电脑USB。OBS保持1920×1080、NV12、30帧。更换码流后手动取消激活/等待2秒/激活采集源。暂不按KEY0。

下一步：OBS开始录制，双击大角标测试图，让R50完整拍到红、绿、黄、蓝四角，固定约20秒；Esc关闭测试图并停止录像。D206诊断格用于读取真实源采集、算法成功数和每行缓存填充耗时，无需人工判断红绿含义。如果板子已断电，先重新下载当前诊断版。

后续修复的独立副本位于 `diagnostics/ddr_hires_read_ahead_20261011`。其连续读取/缓存实现通过原单拍接口回归及缓存一致性、边界、连续数据、协议错误、超时与复位检查；**尚未完成整屏集成/时序资格，尚未上板**。不能用该单元检查声明高清问题已修复。

原A/B/C材料、旧发布、原测试图和Esc行为均保留。只写临时CRAM配置，未写Flash，断电后需重新下载。下面的历史文档或记录中出现的“当前”仅属于当时阶段，以本入口和`docs/hardware_20261009.json`为最新状态。
'''
(R/"docs/当前工程入口_20261011.md").write_text(guide,encoding="utf-8")
note='''# 高清显示排查，2026-10-11

21:13:09与21:14:30两段原始录像已逐字节复制留存。前段由彩条切换到校正窗口顶边细线，后段持续仅显示该细线；样本中窗口904个编码行有900行全黑。NV12/录像编码可能把单条物理行扩散到相邻行，因此不以编码后4行推断板内真实行数。640×904完整图和字迹改善均未接受。

证据：`results/hardware_20261009/hires_display_failure_20261011_211430.json`及该记录中的原片复制、截图与SHA256。对应高清正常码流为7aed，最后一次下载日志为`program_ddr_camera_hires_20261011_190358.log`。基础a4版真实完整矩形校正页的18:12:18录像和约47秒稳定显示证据独立保留，不能把基础验收转用于高清版。

独立迟延模型在每次内存响应增加28个UI周期时复现了同类故障：640个像素正确、其余577920个像素黑色，最大完整行请求耗时5591周期；125MHz UI配合1080p60时一条扫描线预算约1852周期。该结果只是迟延假设下的仿真，不是实测DDR速度。证据：`diagnostics/ddr_hires_deadline_probe_20261011/results/probe.run.log`。

当前D206诊断仍使用960×540源、640×904结果、SCALE1及FIFO1024包。它记录实际接收好坏帧、518400个预期源像素/1080条输入行/64800个包、算法成功/拒绝原因和角标统计；最后64位为显示端完整行请求的最近/最大耗时、完成行数、当前行/状态/拍号。耗时包含DDR响应等待及防止覆盖正在扫描的同奇偶行缓存的等待，不能直接等同于裸DDR单拍延迟。

增加诊断后的第一次布局在beat_data[144]到分布式行RAM数据入口有-0.001ns快速角保持违例，拒绝下载并保存于`diagnostics/ddr_camera_hires_status_20261011/rejected_timing_20261011_213633`。Pango工具不识别旧ram_style属性；按本机ADS官方指南的syn_ramstyle=block_ram修正两条行缓存后，映射到块RAM，八项仿真再次通过，最终时序全部满足。没有新增假路径或放宽约束。

最终D206发布为`release/ddr_camera_hires_status_20261011`，码流614f，21:52:11发起下载并Program/Verify通过。真实D206录制/计数仍待用户提供，高清实际缺行是否恢复也尚未接受。完整工程、源码闭包和检查日志均已留档。

为后续修复准备的单拍接口兼容连续读取副本位于`diagnostics/ddr_hires_read_ahead_20261011`：只在结果区按64字对齐预读8个256bit拍，全部返回后才发布缓存，覆盖缓存块的写操作使其无效。源码区、自检区及写操作保持单拍行为。原接口和缓存/边界/连续返回/错误/超时/复位两项单元检查通过；整屏集成、PDS及时序和真实板卡验收未做，该副本未下载。

协议参照随安装的官方`UG042003_Logos2_HMIC_S_IP.pdf`第31—38页（ARLEN+1个拍、输入读通道没有RREADY）；完整本机PDF复制为`reference/official/PDS_2022.2_UG042003_Logos2_HMIC_S_IP.pdf`。本次公网新版PDF下载中断，残片已改名为`.pdf.partial`，不作为协议依据。

下一步按实际D206计数区分：源帧是否完整、算法是否成功、图像是否发布、显示是否迟到。如果实测支持逐行读取超时，先把连续读取副本接入整屏仿真，增加迟延/争用与换帧检查，经PDS及时序资格后再下载对照；保留已实测基础版随时恢复。
'''
(R/"docs/高清显示排查_20261011.md").write_text(note,encoding="utf-8")
prefix='''## 2026-10-11 最新：高清缺行排查，D206已下载

当前最后一次Program/Verify通过的是`release/ddr_camera_hires_status_20261011`，码流SHA256 `614f6814fe9dad63359176d9cb43a3b4273cf621c7247a3c15e2cafdbde997d7`；960×540源、640×904结果、D206底部诊断格。实际高清正常版录像只出顶边细线，完整高清显示和清晰度提升未验收。当前等待约20秒的大角标诊断实录，读取完整行请求耗时及算法计数。暂不按KEY0，不改OBS参数，桌面控制仍停用。

已实测基础a4版的完整矩形校正页与约47秒短时稳定证据保留，恢复入口为`下载相机校正_重连版.cmd`。第一次诊断布局时序失败已拦截，修正Pango块RAM属性后八项仿真、解码器检查、最终时序与下载回读通过。连续读取修复副本仅通过单元检查，未上板。

最新入口：`docs/当前工程入口_20261011.md`。详细证据与接续：`docs/高清显示排查_20261011.md`、`results/hardware_20261009/hires_status_state_20261011.json`。以下为历史阶段记录，原始A/B/C、旧发布及原测试图保留，未写Flash。

'''
for relative in ["README.md","docs/继续工作.md","docs/相机校正接续_20261011.md"]:
    path=R/relative
    old=path.read_text(encoding="utf-8-sig")
    if "最新：高清缺行排查，D206已下载" not in old:
        path.write_text(prefix+old,encoding="utf-8")
record_path=R/"results/hardware_20261009/hires_diagnostic_progress_20261011.json"
record={"current_board_state":"results/hardware_20261009/hires_status_state_20261011.json",
    "actual_high_detail_picture_accepted":False,"physical_d206_video_pending":True,
    "unit_checked_unprogrammed_fix":"diagnostics/ddr_hires_read_ahead_20261011/results/unit_qualification.json",
    "restore_entry":"下载相机校正_重连版.cmd","next":"Decode unique D206 actual recording, then qualify targeted display fix.",
    "computer_use_paused_by_user":True,"original_materials_modified":False}
record_path.write_text(json.dumps(record,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print("Saved latest D206 entry, rejected timing/failure evidence and the unprogrammed fix status; proven baseline retained.")
