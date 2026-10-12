# 修改后审查摘要

审查范围：S02F1 备份到最新产物（2026-07-12 16:28:12 至 19:01:16）。本包只读取现有文件和日志；未重新运行构建、仿真或下载。当前工程工作树在生成审查包前为 clean。

## 结论表

| 原问题 | 实际修改方法 | 修改文件和位置 | 状态 | 验证证据 | 已知副作用/风险 | 精确回退方法 |
|---|---|---|---|---|---|---|
| S02F1 的 `pixclk_in`、`pix_clk` Setup 违例 | 在像素输入边界增加 `pixclk_in` 寄存器；调整颜色命中对齐为固定 `COLOR_ALIGN_DELAY=6`；保留输出域 pending 寄存器 | `after/source/rtl/HDMI_IN_DDR3_ROI_top/HDMI_IN_DDR3_ROI_top.v:209-253,274,497-504,742-782` | 静态时序完全解决；完整签核部分解决 | 最新 `.rtr`：`pixclk_in` Slow WNS `+0.096 ns`、`pix_clk` `+0.204 ns`，失败端点均为 0；S02F1 为 `-2.471 ns`/`-0.075 ns` | 增加输入/显示路径延迟；跨像素域 ROI pending/hold 的 CDC 没有独立 CDC 报告或板级证据 | 复制 `before/source/rtl/HDMI_IN_DDR3_ROI_top/HDMI_IN_DDR3_ROI_top.v` 覆盖 after 对应文件；该备份为 S02F1 精确前文件 |
| 输入 HSYNC/颜色通路对齐不一致 | 输入数据、VSYNC、HSYNC、DE 统一先寄存；`RGB2YCbCr` 使用 `_q` 输入；颜色 hit 改为单一固定延迟点 | 同上 `:209-253,314-329,497-504`；`after/source/img_process/RGB2YCbCr.v:76-143` | 部分解决 | Compile/Synthesis/PNR 通过；存在新增 `rgb2ycbcr_tb.sv`，但没有本轮运行日志 | 实际算法端到端延迟没有测量；旧 RGB 仿真日志含一次加载失败和最终 `Errors: 2` | 无本轮精确旧文件备份；只能从外部版本恢复，不能把 July-10 baseline 当作精确回退 |
| 车牌框候选误选、远端候选切换过快、边角/稀疏噪声 | 增加 strict/aspect、边角确认帧、全局重搜周期、远端评分比值；把 frame capture/eval 分成流水级；扩大 scorer 用例 | `after/source/rtl/Target_Analysis_Top/Plate_Window_Scorer.v:95-100,248-309,355-404,409-719`；`after/sim_prj/plate_window_scorer_sim/tb/plate_window_scorer_tb.sv:189-514` | 单元级完全解决；系统级部分解决 | `after/verification/plate_window_scorer_sim/transcript`：8 cases、8 logical groups、PASS、0 errors/warnings | ROI 提交时序增加；只验证合成候选模型，未覆盖真实 HDMI+DDR 全链路 | 复制 `before/source/rtl/Target_Analysis_Top/Plate_Window_Scorer.v` 和对应 before testbench 覆盖 after 文件 |
| DDR 帧写入/读取的行计数、bank 切换、复位边界 | 调整 `fram_buf`、`wr_buf`、`rd_buf` 的 frame sync、line trigger、bank/地址计数和 DDR/vout 同步寄存器 | `after/source/rtl/fram_buf.v:100-236`；`after/source/rtl/wr_buf.v:61-323`；`after/source/rtl/rd_buf.v:62-250` | 部分解决/未完成证据闭环 | Compile/Synthesis/PNR/时序均通过；新增 `frame_buffer_control_tb.sv`，但无保存的运行 transcript | DDR 真机读写、跨域脉冲完整性、帧撕裂尚未被仿真或上板证明 | 无本轮精确旧文件备份；需从原始 checkout/外部归档恢复，不能用当前 `rev_1` 生成目录反推 RTL |
| 复位在 PLL 未锁定或外部复位时仍可能释放 | ROI 顶层把 `!locked` 和 `!rst_in` 纳入 cfg 域复位计数，并让 `rstn_out` 与 `rst_in` 相与 | `after/source/rtl/HDMI_IN_DDR3_ROI_top/HDMI_IN_DDR3_ROI_top.v:196-207`；`after/sim_prj/hdmi_roi_top_tb.sv:69-72` | 部分解决 | Compile/Synthesis 通过；testbench 含 reset reassert 检查，但无本轮运行日志 | 只证明 RTL 级预期，未证明 HDMI/DDR 上电时序 | 无本轮精确旧文件备份；从外部版本恢复 |
| 工程配置/IP 刷新后可能与目标器件或源文件不一致 | PDS 重新生成项目/实现脚本及多个 IP 的 `rev_1`、compile、synthesize 产物 | `after/HDMI_IN_DDR3_YCbCr.pds`、`after/impl.tcl`、`after/ipcore/...`、`after/source/rtl/*_fram_buf/...` | 自动刷新已完成；归属未完全确认 | PDS/impl 时间 19:01:16；完整 flow done；编译源清单含 ROI 顶层 | 当前 PNR 对 `hs_in` 报 dangling；CCR 有 53 critical warning；IP 生成物不能替代功能验证 | 若回退工具产物，恢复 `codex_backups/20260710_stage1_baseline` 对应 project/config；这不是 S02F1 精确回退 |
| 接口/约束完整性 | 未发现对 dangling `hs_in` 和未约束 `ddr_init_done` 的闭环修改 | `after/HDMI_IN_DDR3_YCbCr_top.fdc:938-942,1041-1055`；`after/logs/place_route/run.log:317`；`after/logs/report_timing/run.log:93` | 未解决 | PNR：`hs_in` dangling，约束被 ignored；Timing：`ddr_init_done` treated as combinational output；CCR：0 errors、53 critical warnings | HDMI 输入 HSYNC 的物理接口约束未成为有效实现对象；签核边界不完整 | 若只回退约束，恢复 `codex_backups/20260710_stage1_baseline/HDMI_IN_DDR3_YCbCr_top.fdc`；但应先确认当前 top/端口意图 |

## 当前还剩的问题

1. `hs_in` 在 PNR 中是 dangling，相关 `set_input_delay` 不能证明真实 HSYNC 接口时序。
2. `ddr_init_done` 未约束；最新 timing report 的 “All Constraints Met” 不能覆盖该接口。
3. 没有本轮完整 CDC 报告、DDR 真机读写证据、HDMI 输入输出长时间稳定性证据。
4. 只有 scorer 有本轮保存的 PASS transcript；新增 RGB、frame buffer、HDMI top testbench 没有保存运行结果。
5. `place_route/fail_route_nets.txt` 时间为 2026-05-02，早于本轮 PNR，不应作为最新未布通证据；本轮 `run.log` 明确最终 `Unrouted nets ...: 0`。

## 下一步最小修改

先只做接口签核闭环：确认 `hs_in` 是否必须进入实际 HDMI 处理链；若必须，保留并连接到有效输出/处理逻辑后重新生成约束检查；若不需要，从 FDC 删除其 dangling 端口约束。然后为 `ddr_init_done` 增加明确的时钟/接口约束或声明其异步接口。完成后只需重跑 constraint check、timing 和针对受影响 testbench 的最小仿真。
