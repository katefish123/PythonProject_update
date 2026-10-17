"""Publish the current entry only after the actual new Program/Verify receipt."""
from pathlib import Path
import hashlib,json
R=Path(__file__).resolve().parents[1]
hw=R/'results/hardware_20261009'
state=json.loads((hw/'rowtrain_camera_state_20261013.json').read_text(encoding='utf-8-sig'))
main=json.loads((R/'docs/hardware_20261009.json').read_text(encoding='utf-8-sig'))
assert state['program_verify_passed'] and state['current_image_sha256']==main['current_image_sha256']
assert hashlib.sha256((R/state['current_image']).read_bytes()).hexdigest()==state['current_image_sha256']
guide=f'''# 当前工程入口

当前板上为高清行读取修复版，真实Program/Verify已通过。源采样960×540，校正结果640×904，中心显示于1080p画面，没有诊断格。实际稳定性仍待该新码流的短录像验证，不能借用基础版或旧高清版的验收结果。

| 用途 | 文件 |
| --- | --- |
| 当前工程 | diagnostics/ddr_camera_hires_rowtrain_20261013/results/ddr_camera_hires_rowtrain.pds |
| 当前下载入口 | 下载高清校正_行读取修复版.cmd |
| 发布文件和源码快照 | release/ddr_camera_hires_rowtrain_20261013 |
| 当前状态 | results/hardware_20261009/rowtrain_camera_state_20261013.json |
| 问题和修复证据 | docs/高清行读取修复_20261013.md |
| 基础版恢复 | 下载相机校正_重连版.cmd |
| 基础版实际录像证据 | results/hardware_20261009/baseline_recovered_verified_20261012.json |
| 同一张测试图 | 显示相机测试图_大角标.cmd |
| OBS | 打开OBS.cmd |

当前码流SHA256：{state['current_image_sha256']}。
实际下载日志：{state['program_log']}。

十四项检查通过，最终时序满足当前约束，只改变显示读取衔接。相同拥堵模型下，旧显示逻辑第二帧只剩顶边，修复版两帧1157120像素全部正确，最大采集积压24/1024包。模型延迟不是板上实测，实际闪烁是否解决还需录像。

接线：R50→FPGA HDMI-IN；FPGA HDMI-OUT→采集卡；采集卡USB→电脑。相机FHD59.94/HDMI1080p，OBS1920×1080、NV12、30帧。先不按KEY0、不重启相机或拔线。

只需短测试：OBS取消激活采集源，等2秒再激活；开始录制；打开同一大角标测试图，相机位置/焦距/对焦保持，四角完整入镜并固定15—20秒；Esc关闭测试图，回OBS立即点停止录制。确保停止后再回复。这是新修复的验收；先前37分钟原录像已足够分析，不用重录失败版本。

上一版60fb0b53能显示完整校正图，但已确认间歇缺行，其原录像、抽帧和失败记录保存。基础a4可恢复版本保留。原A/B/C、测试图及Esc行为未改，桌面控制仍停用，只写临时CRAM，未写Flash。
'''
(R/'docs/当前工程入口_20261011.md').write_text(guide,encoding='utf-8')
prefix=f'''## 2026-10-13 最新：高清行读取修复版已下载，短验收待完成

当前码流{state['current_image_sha256'][:8]}，Program/Verify通过。完整十四项仿真和最终时序通过，源960×540/结果640×904，只有显示读取衔接变更。旧60fb的实际间歇缺行已由原录像确认；新版本不能沿用旧版或基础版的画面资格。下一步只需同一大角标15—20秒短录像，并明确点击停止录制。当前入口和状态见docs/当前工程入口_20261011.md、results/hardware_20261009/rowtrain_camera_state_20261013.json；原材料和基础版保留。以下为历史记录。

'''
for relative in ['README.md','docs/继续工作.md','docs/相机校正接续_20261011.md']:
    p=R/relative
    old=p.read_text(encoding='utf-8-sig')
    if '高清行读取修复版已下载，短验收待完成' not in old:p.write_text(prefix+old,encoding='utf-8')
print('Current entry published with new-image-only physical acceptance pending.')
