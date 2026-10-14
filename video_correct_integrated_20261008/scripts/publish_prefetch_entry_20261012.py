"""Publish the current programmed entry while keeping pause/older evidence historical."""
from pathlib import Path
import json

R=Path(__file__).resolve().parents[1]
hw=R/"results/hardware_20261009"
state=json.loads((hw/"prefetch_camera_state_20261012.json").read_text(encoding="utf-8-sig"))
assert state["program_verify_passed"] and state["current_image_sha256"]=="60fb0b53a5c13b2c1adf47539c66bb4426d967effa2e3f2a279a9cac09865f22"
main=json.loads((R/"docs/hardware_20261009.json").read_text(encoding="utf-8-sig"))
assert main["current_image_sha256"]==state["current_image_sha256"]
guide='''# 当前工程入口

当前板上为高清连续读取修复版，已经Program/Verify通过。输入1920×1080，源采样960×540，校正结果640×904，直接显示在1080p中心640×904窗口，没有诊断格。实际完整图、清晰度和稳定性仍待新实录确认。

| 用途 | 文件 |
| --- | --- |
| 当前PDS工程 | diagnostics/ddr_camera_hires_prefetch_20261012/results/ddr_camera_hires_prefetch.pds |
| 当前下载入口 | 下载高清校正_连续读取版.cmd |
| 正式码流、资格记录与源码闭包 | release/ddr_camera_hires_prefetch_20261012 |
| 当前状态 | results/hardware_20261009/prefetch_camera_state_20261012.json |
| 实际录像分析入口 | scripts/analyze_prefetch_camera_video_20261012.py |
| 基础版恢复入口 | 下载相机校正_重连版.cmd |
| 基础版真实恢复证据 | results/hardware_20261009/baseline_recovered_verified_20261012.json |
| 原测试图与大角标 | 显示相机测试图.cmd、显示相机测试图_大角标.cmd |
| OBS入口 | 打开OBS.cmd |

当前码流SHA256为60fb0b53a5c13b2c1adf47539c66bb4426d967effa2e3f2a279a9cac09865f22。十二项检查、最终时序、全发布文件校验和本次下载回读均通过。只改变结果区内存读取、顶层启用参数和Pango行缓存属性；106个其余编译文件不变。source_snapshot.zip包含全部编译源、PDS/约束、检查程序和B参考模型/向量。

当前接线保持R50→FPGA HDMI-IN；FPGA HDMI-OUT→采集卡；USB→电脑。R50 FHD59.94/HDMI1080p，OBS保持1920×1080、NV12、30帧。用户准备好后已下载；更换码流后手动取消激活采集源、等2秒、再激活，不拔USB或HDMI。

新测试：保持相机位置/焦距/对焦，OBS录制，同一大角标测试图四角完整入镜、白色纸页尽量占满，固定30秒；Esc关闭测试图再录5秒。先不按KEY0。测试图中320×452只是原始图上的文字，芯片当前结果为640×904；原图与Esc行为保持不变。

新的录像只用专用prefetch分析入口，它检查当前码流身份。旧--hires入口绑定7aed旧版，不能拿来评价这次新码流。仿真时间不是实测DDR速度或算法FPS，静态/保留上一帧也不能证明持续更新帧率。当前图像资格未接受。

基础a4曾在明确经FPGA链路的00:37:42实际录像中显示完整校正图，首次图出现后的约52秒没有黑屏/退彩条；它和旧高清失败证据保留。原A/B/C及原测试图未改，只写临时CRAM，未写Flash。桌面控制仍停用。
'''
guide+="\n本次下载日志："+state["program_log"]+"。\n"
(R/"docs/当前工程入口_20261011.md").write_text(guide,encoding="utf-8")
prefix='''## 2026-10-12 最新：高清连续读取版已下载，实际画面待验证

已按用户“继续”恢复工作。正式发布release/ddr_camera_hires_prefetch_20261012已封装；十二项检查、最终时序和全文件校验通过，新Program/Verify通过。当前码流60fb0b53，源960×540、结果640×904、没有诊断格。实际高清图与清晰度仍等待用户同一大角标录像；基础a4可用版本、实际恢复证据和全部原材料保留。暂停记录属于历史，以docs/当前工程入口_20261011.md及results/hardware_20261009/prefetch_camera_state_20261012.json为最新状态。以下为历史阶段记录。

'''
for relative in ["README.md","docs/继续工作.md","docs/相机校正接续_20261011.md"]:
    p=R/relative
    old=p.read_text(encoding="utf-8-sig")
    if "高清连续读取版已下载，实际画面待验证" not in old:p.write_text(prefix+old,encoding="utf-8")
record={"resumed_at_utc":state["recorded_at_utc"],"paused_by_user":False,
 "current_state":"results/hardware_20261009/prefetch_camera_state_20261012.json",
 "release_sealed":True,"program_verify_passed":True,"actual_camera_picture_accepted":False,
 "next":"Manual OBS activation and same-target physical video; decode/visually review before acceptance."}
(hw/"resume_prefetch_20261012.json").write_text(json.dumps(record,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print("Published current prefetch entry and actual-image pending scope; prior pause/working baseline kept.")
