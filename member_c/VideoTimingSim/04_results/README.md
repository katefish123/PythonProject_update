# 仿真结果

## V5 本轮复核（2026-10-05）

| 脚本 | 成功标志 | 检查范围 |
| --- | --- | --- |
| run_ms7210_check.do | TEST_PASS_MS7210_CONFIG | 实际SCL/SDA、缺设备不完成、校验读回、51次写及2次读、完成后复位清除标志 |
| run_hdmi_real_compile.do | TEST_PASS_HDMI_REAL_COMPILE | 完整真实源码与PDS GPLL模型编译载入，不运行完整视频行为 |
| run_tpg_check.do | TEST_PASS_TPG | TPG模式回归 |
| run_top_check.do | TEST_PASS_TOP | VTC/TPG顶层回归 |
| run_1080p_check.do | TEST_PASS_1080P | 2475000像素位置的一帧检查 |
| run_hdmi_board_check.do | TEST_PASS_HDMI_TOP | 原板级行为模型连接检查 |

以上六项的本轮编译/载入/仿真日志均为0 Errors、0 Warnings。新增日志为 `ms7210_config_check.log` 和 `hdmi_real_compile.log`。测试模拟的寄存器应答不能证明真实MS7210画面输出；硬件仍待PDS完整编译与上板验收。

下面PLL自带测试保留2026-10-04历史结果，本轮未改PLL。教学波形脚本保留，未在本轮重跑。

## PDS PLL 生成与检查

- 检查日期：2026-10-04
- 器件：`PG2L100H / -6 / FBG676`
- `video_pll_27m_148m5`：27 MHz → 148.5 MHz，PDS 生成 0 Errors、0 Warnings
- `config_pll_27m_10m`：27 MHz → 10 MHz，PDS 生成 0 Errors、0 Warnings
- 两个生成模块与 PDS 官方 `GTP_GPLL` 模型：ModelSim 编译 0 Errors、0 Warnings
- 两个 PDS 自动生成的 Testbench：`Simulation Success`，0 Errors、0 Warnings
- PDS 原始生成日志：分别位于两个 `01_design_code/ip/<PLL名>/generate.log`

## HDMI 板级连接检查

- 检查日期：2026-10-04
- 检查内容：两路 PLL 接口、MS7210 复位延时、初始化完成、VTC/TPG 到 HDMI 输出端口的连接
- 测试方式：PLL 和 MS7210 控制器使用仿真模型，现有 VTC/TPG 使用真实工程代码
- 编译结果：0 Errors，0 Warnings
- 仿真结论：`TEST_PASS_HDMI_TOP`
- 详细输出：`hdmi_board_check.log`
- 边界：该结果证明连接逻辑正确，不等同于真实 PDS PLL、寄存器初始化和引脚约束已经完成

## 顶层集成检查

- 检查日期：2026-10-01
- 缩小总时序：14 x 7
- 检查像素位置：98
- 检查内容：VTC/TPG 连接、同步、`de`、消隐和四种图案选择
- 编译结果：0 Errors，0 Warnings
- 仿真结论：`TEST_PASS_TOP: VTC and TPG top-level integration is correct`
- 详细输出：`top_check.log`

## 1080p60 正式参数检查

- 最近复查：2026-10-01
- 总时序：2200 x 1125
- 有效画面：1920 x 1080
- 检查像素位置：2475000
- 检查行数：1125
- 编译结果：0 Errors，0 Warnings
- 仿真结论：`TEST_PASS_1080P`
- 模块结构：独立 VTC `video_timing_vtc` + 独立 TPG `test_pattern_generator_tpg`

详细 ModelSim 输出见 `1080p_check.log`。

## 教学仿真

- 缩小时序：14 x 7
- 检查内容：计数器、同步信号、有效区、红绿蓝白彩条、整帧回绕
- 仿真结论：`TEST_PASS: complete video timing and RGB output are correct`

## TPG 独立仿真

- 检查内容：消隐区、竖彩条、纯色、四象限和保留模式
- 仿真结论：`TEST_PASS_TPG: all pattern modes are correct`
- 详细输出：`tpg_check.log`

## PDS V5

完整构建报告、34个管脚验证、时序报告、下载文件和SHA256见 `pds_v5/README.md`。内部时序通过，外部接口时序与上板画面仍待验收。
