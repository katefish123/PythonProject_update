# 验证摘要

本响应没有重新运行验证。

## 已有运行证据

| 用例 | 结果 | 证据 | 验证内容 |
|---|---|---|---|
| Plate_Window_Scorer A02R1 | PASS，8 cases、8 logical groups、0 errors/warnings | `after/verification/plate_window_scorer_sim/transcript` | 空帧、严格候选、远端候选优先级、宽松候选、稳定提交、稀疏干扰、分离目标不合并 |
| 旧 RGB/YCbCr ModelSim | 不作为 clean PASS；日志包含一次 design load error，后续编译成功，但最终 `Errors: 2` | `after/verification/img_ycbcr_sim_prj/sim/behav/run_behav_simulate.log` | 旧图像处理向量/`img_process.txt` 流程；不是本轮可信通过证据 |
| Compile/Synthesis/PNR/Timing/Bitstream | PASS/完成 | `after/logs/run.log` | 编译、综合、映射、布线、报告、bitstream 产出 |

## 本轮新增但没有运行记录的 testbench

- `after/sim_prj/frame_buffer_control_tb.sv`：应覆盖 frame write/read bank、line trigger；没有保存 transcript。
- `after/sim_prj/rgb2ycbcr_tb.sv`：应覆盖黑/白/基本 RGB 到 YCbCr；没有保存 transcript。
- `after/sim_prj/hdmi_roi_top_tb.sv`：包含复位重新拉低检查并输出 `HDMI_ROI_TOP_PASS`；没有保存 transcript。

## 延迟变化

- `HDMI_IN_DDR3_ROI_top.v` 新增 `pixclk_in` 输入边界寄存器，颜色对齐由窗口改为固定 `COLOR_ALIGN_DELAY=6`；因此输入到颜色命中路径至少增加/重定相了一个像素时钟阶段。
- `Plate_Window_Scorer.v` 将 `frame_event_top -> frame_capture_top -> frame_eval_top` 分级；ROI 公共输出的提交时刻改变。A02R1 testbench 已按新的时序检查，但没有完整系统延迟测量。
- DDR/HDMI 输出端到端算法延迟没有可比的 before/after 波形证据。

## 上板状态

- 未发现下载器、JTAG、板卡串口、HDMI 采集/输出或 DDR 校验日志。
- 因此：没有上板验证证据。

## 已覆盖与未覆盖

- HDMI：仅有静态端口/时钟实现证据和未运行的 top testbench；未验证真实 1080p60 输入输出。
- DDR：仅有 PNR 和结构化 RTL/未运行 testbench；未验证初始化、读写、bank 切换、帧撕裂。
- 复位：RTL 中增加 `!locked`/`!rst_in` 复位门控；未完成实际上电时序验证。
- 检测：scorer 单元测试通过；未验证真实色彩分割、Sobel、run/link、ROI 在 DDR 回读后的组合效果。
- 画框：顶层存在 pending/显示域寄存器；未上板观察框位置、闪烁、跨帧稳定性。
- CDC：没有独立 CDC 工具报告或人工逐网表签核。
- 约束：CCR 0 errors、53 critical warnings；`hs_in` dangling、`ddr_init_done` unconstrained 仍未闭环。
