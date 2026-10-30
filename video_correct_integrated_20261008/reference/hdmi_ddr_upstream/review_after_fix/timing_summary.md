# 时序审查摘要

来源：`after/reports/report_timing/HDMI_IN_DDR3_ROI_top.rtr`，Fabric Compiler 2022.2-SP6.4，最新文件时间 2026-07-12 18:59:52。没有重跑 timing。

## 像素时钟摘要

| 时钟/角 | Setup WNS ns | Setup TNS ns | Setup failing endpoints | Hold/WHS ns | Hold failing | Recovery WNS ns | Recovery failing |
|---|---:|---:|---:|---:|---:|---:|---:|
| `pixclk_in` Slow | +0.096 | 0.000 | 0 | +0.167 | 0 | +3.249 | 0 |
| `pix_clk` Slow | +0.204 | 0.000 | 0 | +0.304 | 0 | +3.549 | 0 |
| `pixclk_in` Fast | +0.663 | 0.000 | 0 | +0.105 | 0 | +4.543 | 0 |
| `pix_clk` Fast | +2.689 | 0.000 | 0 | +0.201 | 0 | +4.734 | 0 |

Removal 也无失败端点：Slow `pixclk_in` 0.590 ns、`pix_clk` 0.451 ns；Fast `pixclk_in` 0.399 ns、`pix_clk` 0.304 ns。

## 与 S-02F1 对比

| 项目 | S-02F1 | 当前 | 变化 |
|---|---:|---:|---:|
| `pixclk_in` Slow Setup WNS | -2.471 ns | +0.096 ns | +2.567 ns |
| `pixclk_in` Slow Setup TNS | -1024.035 ns | 0.000 ns | 清零 |
| `pixclk_in` Slow 失败端点 | 756 | 0 | 清零 |
| `pix_clk` Slow Setup WNS | -0.075 ns | +0.204 ns | +0.279 ns |
| `pix_clk` Slow Setup TNS | -0.075 ns | 0.000 ns | 清零 |
| `pix_clk` Slow 失败端点 | 1 | 0 | 清零 |

## 当前最差 Setup 路径

报告每个 path group/corner 实际只输出 3 条 worst path；下表从现有 Slow/ Fast Setup 块中各像素域选取可见的最差 5 条，不把报告不存在的路径补造为“Top 10”。逻辑级数来自 `Data arrival time ... Logic Levels`。

### `pixclk_in`

| Corner | Slack ns | Startpoint | Endpoint | Logic levels | 模块 | 报告行 |
|---|---:|---|---|---:|---|---:|
| Slow | 0.096 | `u_Plate_Window_Scorer/lock_y1[0].../CLK` | `u_Plate_Window_Scorer/lock_x1[6].../CE` | 12 | `u_Plate_Window_Scorer` | 2241 |
| Slow | 0.096 | `u_Plate_Window_Scorer/lock_y1[0].../CLK` | `u_Plate_Window_Scorer/lock_x2[1].../CE` | 12 | `u_Plate_Window_Scorer` | 2322 |
| Slow | 0.097 | `u_Plate_Window_Scorer/lock_y1[0].../CLK` | `u_Plate_Window_Scorer/roi_x1[1].../I4` | 12 | `u_Plate_Window_Scorer` | 2403 |
| Fast | 0.663 | `b_in[7] (port)` | `RGB2YCbCr_inst/N56/gopapm/X[7]` | 2 | `RGB2YCbCr_inst` | 6859 |
| Fast | 0.671 | `g_in[1] (port)` | `RGB2YCbCr_inst/N33/gopapm/X[1]` | 2 | `RGB2YCbCr_inst` | 6912 |

### `pix_clk`

| Corner | Slack ns | Startpoint | Endpoint | Logic levels | 模块 | 报告行 |
|---|---:|---|---|---:|---|---:|
| Slow | 0.204 | `fram_buf/rd_buf/init_done_vout_d1.../CLK` | `g_out_obuf[1]...TX_DATA[0]` | 1 | `fram_buf/rd_buf` + output IOB | 601 |
| Slow | 0.338 | `fram_buf/rd_buf/init_done_vout_d1.../CLK` | `de_out_obuf...TX_DATA[0]` | 1 | `fram_buf/rd_buf` + output IOB | 664 |
| Slow | 0.356 | `fram_buf/rd_buf/init_done_vout_d1.../CLK` | `b_out_obuf[7]...TX_DATA[0]` | 1 | `fram_buf/rd_buf` + output IOB | 727 |
| Fast | 2.689 | `fram_buf/rd_buf/init_done_vout_d1.../CLK` | `g_out_obuf[1]...TX_DATA[0]` | 1 | `fram_buf/rd_buf` + output IOB | 5219 |
| Fast | 2.783 | `fram_buf/rd_buf/init_done_vout_d1.../CLK` | `b_out_obuf[7]...TX_DATA[0]` | 1 | `fram_buf/rd_buf` + output IOB | 5282 |

## 148.5 MHz 判定

- 静态 Setup/Hold/Recovery/Removal：通过，两个像素域在 Slow/Fast 均为正 slack，失败端点为 0。
- 完整评审签核：不签核。原因是 CCR 有 53 个 critical warning，PNR 报告 `hs_in` dangling，timing 报告提示 `ddr_init_done` 未约束，且没有独立 CDC/板级证据。
