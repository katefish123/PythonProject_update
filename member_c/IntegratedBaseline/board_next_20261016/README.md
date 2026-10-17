# C 整板 V5C：原生 RAW、彩色角标校正与共同恢复

这是 `c-pipeline-next` 独立整板候选。**PDS全部最终约束通过**，快慢两个工艺角100条汇总记录均无失败端点。冻结 V4S 和 B 原始数学算法保持不变，本任务未烧板，硬件验收仍未完成。

交付：[sbit](release_candidate_v5c/video_correct_ddr_top.sbit)、[smsk](release_candidate_v5c/video_correct_ddr_top.smsk)、[PDS完整输入与工程包](release_candidate_v5c/V5C_PDS_source_project.zip)、[精确SHA及最终时序回执](evidence/v5c/implementation.json)。sbit SHA256：`d249b55e01199b7d6106ca009b9ca562273a1e502e13d5bfb13d761a95bfcbda`。本轮完整实现耗时22分6秒；重建仍须重新检查时序。

## 本轮完成

- RAW 完整1920×1080、逐像素1:1，不等待角标。双源缓存保护保留；发布窗口放入前置消隐区，并限制每次扫描最多接收一张新图，解决错过单一发布时刻后的额外等待。原生DDR完整尺寸仿真稳定约 **30张新图/秒**，改变相机相位后也通过。
- 校正只接受同一源bank/帧号的合法彩色四角：红左上、绿右上、黄右下、蓝左下。检查像素数、包围框、密度、边长、凸性和面积，允许纸张整体处于画面一侧。黑色固定ROI模式不保证任意位置黑角标识别。
- 保留B算法，校正有效765×1080、存储768×1080，左1右2列补黑、居中放入1920×1080 HDMI画布，保持目标比例。完整写入退休后才能发布；旧RAW显示确认前不归还源缓存。
- 整板接入RAW/CORRECTED/HELD、真实显示bank/帧号、已完成校正H/角点/DDR地址、物理输入计数、FIFO峰值、服务等待、当前故障与首次历史事件。
- 内存、应用、跨域队列、显示所有权共同硬恢复；最多自动重试三次，耗尽后保持复位，手动重新启动。真实保护通道独立于诊断快照，历史ALIGN不冒充当前源错误。

## 已验证

[十组精确源码回归证据](evidence/v5c/summary.json) 绑定实际编译快照与最终146个PDS输入：

- RAW原生DDR：灰阶及独立RGB三通道图案分别验证12个实际扫描帧号、45,619,200个HDMI像素，稳定发布间隔约33.3ms；缓存不得覆盖、相位偏移均检查。
- 校正原生DDR：交替两幅不同位置原始1920×1080 RGB图，插入一帧无角标坏图；6个实际扫描帧号、14,515,200像素，以及四角、九项H、实际DDR结果与HDMI输出逐一比较。坏图拒绝后恢复。
- 整板恢复：源故障标志、ALIGN脉冲、PHY故障、实际服务超时、共同复位、恢复RAW、重试耗尽和手动重启。只有PLL/配置/物理DDR IP边界为测试替身，未模拟真实PHY。
- 显示窗口、延迟响应与复位、CDC快照、同拍AR/R、真实旧ROI误判反例均有测试。[独立审查](review/v5c_review.md) 发现的两项问题已先复现失败，再修复回归。

旧 `evidence/summary.json` 只记录9ff9629应用层阶段，不能作为本轮证明。模型包含AW/W/AR/R等待，但不包含真实DDR训练、DQS或DRAM刷新；仿真不代替实板验收。

2026-10-17补充：[黑标原图离线B RTL对照](review/offline_black_20261017/README.md)。电脑给定正确四角后，826200个实际RTL输出像素与定点参考一致；7个B源文件SHA与V5C相同。外框拉正但内部网格仍有偏斜；该实验绕过板端检测、DDR及HDMI，不改变本版硬件未验收状态。

## 复现与交接

本机依赖冻结基线 `D:/FPGA/output/c_stream_board_v4s_20261016`、ModelSim及仓库Python软件参考。依次生成 display/prepare_display.py、build_integration.py、prepare_pipeline_fixtures.py、build_board.py。

```powershell
& member_c/IntegratedBaseline/board_next_20261016/run_integration.ps1 -Suffix fresh_raw -Native -Frames 12
& member_c/IntegratedBaseline/board_next_20261016/run_integration.ps1 -Suffix fresh_corr -Native -Corrected -Frames 6
& member_c/IntegratedBaseline/board_next_20261016/board/run_recovery.ps1 -Suffix fresh_recovery
python member_c/IntegratedBaseline/board_next_20261016/collect_v5c.py
```

每次使用新后缀保留证据。`integration/sources.json` 是应用清单；`board/source_manifest.json` 才是145个设计文件和1个约束的整板清单。最终实现使用独立冻结副本；重新构建必须重新检查时序。

操作及HEX字段见 [硬件交接](board/HANDOFF.md)，配套打印页见 [四色角标页](geometry/fixtures/matching_four_color_test_page.pdf)。诊断OSD覆盖RAW部分画面，底层源图仍完整保存。

仍需硬件聊天完成精确SHA烧录、原生画质对照、四角与内部网格、运动/重连/长期运行和真实新图速率验收。实际模糊、OVER与PHY根因尚未证明解决，也未证明连续60张新校正图/秒；HDMI扫描不能冒充新图数量。
