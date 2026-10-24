# 2026-10-22 实际烧录结果

已写入 PG2L100H 临时 CRAM，Program 和 Verify 均成功。Flash 未写入。

码流 SHA256：`780c9740421a1db2e4015be20ec860bfe1b1ba2613deca519f937f77db6cae6f`。

完整最终时序 10 节、100 行汇总全部通过，逐项时钟域与冻结基线核对；应用层校正/RAW 原生仿真通过。采用 route91 已完成的第 1 轮布线 DB 独立复制，再次运行完整 timing worker 后生成资格；未采用后续正在优化的 DB。

本机证据：`D:\FPGA\output\b_lens_board_trial_20261022_v5\release_qualified_iteration1` 内 qualification.json、program.log、hardware_programming.json；对应源码 `D:\FPGA\output\b_lens_board_trial_20261022_v5\sources`。

OBS 已从采集卡“未识别到视频信号输入”切为 FPGA 诊断彩条，状态 INPUT。输出链路有信号；尚无相机实景，已请用户唤醒相机、必要时拔插相机端 HDMI。不能把本次结果称为相机校正画面或清晰度/刷新率验收。

默认镜头校正，按住 KEY1 请求 RAW；本版本是 B 的 R50/18mm 镜头全图试标定实验，不是最终自动纸框局部校正工程。

后续输入排查：用户确认 HDMI 分辨率1080p。OBS 状态为 NO COMPLETE FRAME；临时输入测量程序 Program/Verify 通过，70次样本的行宽/行数不稳定，未形成固定1920×1080输入。采集数据需按原测量程序逆序解码垂直行（measurement_decoded.json），原始 measurement.json 为未校正读数，不能作尺寸依据。测量程序不含B算法、DDR，故当前错误不能解释为B算法输出帧率不匹配。探针与本版接收引脚位置逐项相同。测后已恢复已资格化的校正码流，Program/Verify 成功，日志 D:/FPGA/output/b_lens_input_check_20261022/restore_corrected_program.log。OBS曾冻结旧画面，已重新激活采集；未完成实景验收。
