# 2026-10-22 上板构建状态

本次用户明确要求下载 B 最新交付并立即上板测试。目标 PG2L100H，临时 CRAM，Flash 不变。

- B 来源：main-B 510c040f8da06e67f5b9b64f9c851dffeff3a8b0。
- 原包 SHA256：628f0d261ad24d2a4328f6996da98af8a5213514fa811050b62a7783e8b1958e。
- B 原生 11 项测试通过；应用层全宽校正及 RAW 两幅不同源回归通过。
- JTAG 已识别 USB Cable II 和 PG2L100H；scan_chain_third.log 是扫描证据，不是新版烧录证据。
- v5/seed17 全流程完成，但最终慢角 DDR setup -0.350ns（3 个端点），processing hold -0.001ns（1 个端点）。该实现拒绝烧录，不能用工具生成了 .sbit 代替时序合格。
- seed41b 映射 DB 直接重布线在 DDR PHY 放置失败，拒绝。
- 当前 v5/seed73 从同一组 SHA 约束的源码重新综合和映射，仅改变布局布线随机种子，最终资格待查。
- 新版尚未烧录。最后结果必须同时有 qualification.json 和 hardware_programming.json，且 program.log 包含 Program 与 Verify 成功。

本机根目录：D:/FPGA/output/b_lens_board_trial_20261022_v5。当前 OBS 显示采集卡“未识别到视频信号输入”，仍需烧录后实查视频。

更新：seed73 的 after-hold 内部汇总曾显示通过，但独立完整 .rtr 最终仍有 DDR cache 查找 setup -0.035ns、4 个失败端点；该实现也拒绝烧录。已实际验证 qualifier 会因 Final timing not met 拒绝它。route91 从 SHA 绑定的 seed73 mapped/placed DB 与生成 PCF 复用布局，只重新布线；使用 performance、额外 0.2ns 路由目标和 50ps 保持修复目标，不修改 RTL、FDC 或时钟。route91 最终检查待完成。

发布 helper 已独立复核；三个入口显式拒绝优化 Python 模式，避免 -O 去掉断言检查。qualify 逐项校验最终报告和输入 SHA；program_verified 只执行已资格化的 CRAM 写入并要求真实 Program、Verify 成功文本，才写硬件成功记录。

最终更新：已选定 route91 完成的第1轮，复制独立 DB 并重跑完整最终报告后，100行时序全部通过；20:16:53（北京时间）完成 CRAM Program+Verify。实际状态以 HARDWARE_RESULT.md 和 release_qualified_iteration1 的硬件记录为准。OBS 已收到彩条，状态 INPUT；等待相机唤醒。
# 2026-10-23 接收边沿及重定时增量

当前最新候选改为 `D:/FPGA/output/b_lens_board_release_20261023`：在双级 RX 基础上移除固定镜头模式未使用的 marker metadata 分支；完整帧/DDR ACK/银行保护保持。三组全高清校正、RAW及独立异常输入/所有权回归通过。完整 PDS 已进入布局（利用率45%），尚待最终时序资格，未烧录。

- 单独下降沿的完整候选 `b_lens_board_rxedge_20261023`：最终时序未通过，资格拒绝，未烧录。
- 双级完整候选 `b_lens_board_rxretime_20261023`：完整两组校正、实际 VS 恢复链路、RAW、相位模型和 I²C 配置回归均通过。144 端口位、147 设计文件及约束/EDID/DDR 地址离线核验通过。
- 双级默认构建最终时序仍有 RX setup -0.271ns、处理域 -0.644ns、DDR 跨域 -0.563ns，资格拒绝，未烧录。正在对同一份源码、映射及放置 DB 做 performance 布线，输入哈希保存于 `performance/input_binding.json`。
- 用户接线断开后不再烧录。最终十类时序及全部证据校验未通过前，不生成可烧录交付包。此前独立诊断已见相机实景但偏绿；不能把离线通过写为实景验收。


最新候选 release2：上版完整最终报告拒绝（DDR PHY setup -1.083ns、独立输入计数 RX hold -0.716ns）。现修正独立计数的采样边沿，保持独立复位；完整 PDS 从头构建并启用单元复制优化长扇出，最多三轮时序约束布线。最终资格待生成，未接触硬件。

最终离线更新：release2第三轮及独立最终report_timing全部100行通过，最小余量+0.002ns；qualify_lens_release2.py实际通过，码流SHA256 1aa627aec2fce54cf2b0a8c0357d732b455d71f6f0ace00831cd833063350351。仅达到离线上板候选资格，未烧录、未实景验收。

交付完成：D:/FPGA/deliveries/FullHD_Lens_Integrated_20261023.zip，ZIP SHA256 680f5757082935fd6c7d6ecdac5d75e5e089d67851b22a66ae97ca0f693bb158。包内PDS实际Compile通过；ZIP解压到不同目录再次Compile通过；两处只读完整性检查通过且未创建program_logs。独立复核224项文件哈希及100行时序，无Critical/Important。新版仍未烧录/实景验收。
