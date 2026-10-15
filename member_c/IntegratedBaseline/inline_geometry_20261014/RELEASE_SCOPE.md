# 发布包适用范围

本包仅用于离线黑标接口整合、功能仿真和PDS时序研究。即便包内包含sbit及通过的仿真/时序报告，也不应替换当前板上程序。

- 尚未合入烧录聊天当前 `540dd628d92dbd477e6f8cbd4ccf7d0ebffbd1ae067929dc10015a7ae1a7793f` 基线的原子采集突发和诊断预览修正。后续需适配双源缓冲、突发载荷及缓存失效，再重新验收。
- 完整1920×1080源图、640×904结果。采用固定ROI黑色角标，不能直接沿用四色目标。
- 三帧完整模型平均启动间隔约508ms，没有达到连续实时视频目标；HDMI扫描60Hz不能作为校正帧率。
- 三帧功能回归不能证明持续吞吐、真实端到端延迟、清晰度或长期稳定性。几何拒绝/坏采集的整核恢复尚需补测。
- 未执行本候选的板级Program/Verify或实拍验收，`hardware_accepted=false`，`board_replacement_allowed=false`。

当前板上程序由“明确烧录专用需求”聊天统一管理。需要继续开发空间块邻域收集、处理流水线及连续采集协议，并完成完整回归、最终时序和板测后，才能形成后续正式候选。

完整开发记录：[GitHub开发目录](https://github.com/katefish123/PythonProject_update/tree/c-pipeline-next/member_c/IntegratedBaseline/inline_geometry_20261014)。
