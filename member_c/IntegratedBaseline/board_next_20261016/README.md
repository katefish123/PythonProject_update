# C 新应用层候选：原生 RAW、彩色角标和校正显示

这是 `c-pipeline-next` 的独立开发候选。冻结的 V4S RTL、sbit、发布回执未替换；B 的原始 RTL 与数学算法未修改。**本目录不是已经完成 PDS、可直接烧录的整板交付。**

## 本轮实际改动

- 新帧管理器支持 RAW：源帧全部写入 DDR 并收到终结确认后即可发布，不等待角标或 H。没有角标不再导致 RAW 被拒绝；写入形状或溢出错误仍会拒绝。
- RAW 显示完整 1920×1080，按原比例逐像素读取源 DDR，不走低清预览、透视或拉伸。校正显示有效 765×1080，存储 768×1080，左 1、右 2 列黑边，居中放入 1920×1080 HDMI 画布。
- 同一 VTC 在帧边界接收 RAW/CORRECTED 发布。模式、bank、帧代号和行请求共同保持到确认。RAW 仍在显示时，源缓存保持占用；只有下一次显示切换确认后才能归还。
- 晚到的角标元数据不会改写已经 VALID 的描述符，也不会附着到复用后的新帧。校正模式仍等待同一 bank、同一代号的有效角点。
- 彩色角标前端统一 RX 和处理域的分类规则：红左上、绿右上、黄右下、蓝左下；加入像素数、包围框、密度、边长、凸性和面积检查。未要求纸张分布在画面四个象限。黑色固定 ROI 模式仅保留作受限兼容，不代表任意黑角标纸张均可识别。
- 显示行邮箱的两个消费者共用一条 ACK 同步链，避免物理同步延迟偏差导致旧元数据未接收完就覆盖请求。
- 独立故障观测模块区分当前故障和首次历史事件；独立恢复控制器验证了完整复位保持时间、训练等待及最多三次重试。**这两项尚未接入整板顶层，不能宣称板上停帧已修复。**

## 已验证与性能边界

`evidence/summary.json` 记录精确结果、输入 SHA256 和日志。

1. RAW 原生 1920×1080 整链路仿真经过真实应用 RTL、原生突发适配器和带 AW/W/AR/R 等待的内存模型；测试不同灰阶移动帧、实际源缓存写入、实际扫描像素，以及显示缓存不得被采集覆盖。模型不包含 DDR PHY、校准或真实 DRAM 刷新。
2. 校正整链路从原始 RGB 测试图提取四个彩色角点，进入原 B 算法，逐点比较实际 DDR 结果写入和 HDMI 输出。完整尺寸采用原始 1920×1080 合成图及 765×1080 有效软件参考。该测试是已知图形的数字验证，不能代替相机实拍几何验收。
3. 独立 Fraction 几何约束审计、两组 H/坐标网格、五组彩色图像、十二类检测条件、1080p 事件跨时钟及描述符背压均有局部测试。
4. 控制器检查 RAW 不启动 B、显示 ACK 前不归还旧 RAW、RAW→校正切换、软中止先排空、硬故障保持所有权到共同复位，以及禁止对仍在显示的 RAW bank 启动校正。

**RAW 刷新速度尚未完成优化。** 当前双源 bank 的安全占用策略在原生测试中稳定约每三个 HDMI 扫描周期发布一张新图，即约 20 张新图/秒。HDMI 扫描仍是 60 次/秒，重复扫描不能计为新图。下一步要优化源 bank 数量或调度期限，并重新验证容量、读写所有权和 DDR 服务间隙，不能解除缓存保护来伪造速度。

## 复现

本机依赖冻结基线 `D:/FPGA/output/c_stream_board_v4s_20261016`、ModelSim 和原仓库 Python 软件参考。运行：

```powershell
python member_c/IntegratedBaseline/board_next_20261016/build_integration.py
python member_c/IntegratedBaseline/board_next_20261016/prepare_pipeline_fixtures.py
& member_c/IntegratedBaseline/board_next_20261016/run_integration.ps1 -Suffix your_fresh_suffix -Native
& member_c/IntegratedBaseline/board_next_20261016/run_integration.ps1 -Suffix your_other_fresh_suffix -Native -Corrected
```

每次测试保存实际编译的源快照及哈希；使用新后缀，避免覆盖证据。`integration/sources.json` 是应用层编译输入，**不是整板 PDS 工程清单**。

## 仍未完成，交接时必须说明

- RAW 达到连续 60 张不同图像/秒；持续移动输入、长 DDR 服务间隙和高负载下的丢帧定位。
- 新应用层与整板顶层的模式控制、RAW/CORRECTED/HELD 状态、角点/H/帧号快照及当前/历史故障显示接线。
- 完整内存/应用协同恢复的整机故障注入，以及真实板子首次 ALIGN/停帧原因的定位。
- 新候选的 PDS 综合、布局布线、全部约束时序和新 sbit；当前不能沿用 V4S 的时序通过结论。
- 相机实拍的纸张端点、内部网格、清晰度、实际更新率和长期稳定性验收。

匹配本检测器的打印材料见 [四彩角标测试页](geometry/fixtures/matching_four_color_test_page.pdf)。`review/materials` 中的板测截图只作故障证据，未冒充原始相机输入。硬件聊天负责烧录与 OBS 验收，本轮未操作板子。
