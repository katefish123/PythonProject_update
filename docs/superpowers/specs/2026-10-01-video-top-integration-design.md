# 成员 C：VTC 与 TPG 顶层集成设计

## 背景

当前工程已经分别实现并验证：

- `video_timing_vtc.v`：产生 `h_cnt`、`v_cnt`、`hsync`、`vsync` 和 `de`。
- `test_pattern_generator_tpg.v`：根据坐标、`de` 和 `pattern_sel` 产生 RGB 测试图案。

两个模块目前只在 Testbench 中连接，还没有可用于综合的正式顶层模块。VTC、TPG 和 Testbench 还分别保存了部分相同的时序参数，后续修改分辨率时存在参数不一致的风险。

## 本阶段目标

1. 新增可综合的 `video_top.v`，负责连接 VTC 与 TPG。
2. 由顶层统一接收并向两个子模块传递视频时序参数。
3. 保留当前 VTC、TPG 的行为和 1920×1080 默认参数。
4. 新增自检查顶层仿真，验证模块连接、图案选择和消隐输出。
5. 对正式设计文件启用隐式网络防护，及时发现拼错的信号名。

## 非目标

本阶段不加入以下内容：

- RGB 或同步信号流水线；
- AXI4-Stream、AXI4-Lite 或运行时寄存器；
- FPGA 内部 TMDS 编码及 HDMI 音频；
- MS7210 初始化、PLL、PDS 管脚约束；
- DDR3 帧缓存和图像旋转算法；
- 4K 或动态分辨率切换。

这些内容只有在开发板、官方例程或 PDS 时序报告提出明确需求后再设计。

## 顶层接口

`video_top` 对外提供：

| 信号 | 方向 | 位宽 | 用途 |
| --- | --- | ---: | --- |
| `clk` | 输入 | 1 | 像素时钟 |
| `rst_n` | 输入 | 1 | 低电平复位 |
| `pattern_sel` | 输入 | 2 | 选择彩条、纯色、四象限或黑色 |
| `hsync` | 输出 | 1 | 行同步 |
| `vsync` | 输出 | 1 | 场同步 |
| `de` | 输出 | 1 | 有效画面指示 |
| `rgb` | 输出 | 24 | `R[23:16]、G[15:8]、B[7:0]` |

`h_cnt` 和 `v_cnt` 只连接 VTC 与 TPG，不作为顶层外部接口。

## 参数与数据流

顶层保存 `H_SYNC`、`H_BACK`、`H_ACTIVE`、`H_FRONT`、`V_SYNC`、`V_BACK`、`V_ACTIVE`、`V_FRONT`、同步极性和纯色值。

顶层计算：

- `H_ACTIVE_START = H_SYNC + H_BACK`
- `V_ACTIVE_START = V_SYNC + V_BACK`

然后把同一组参数分别传给 `u_vtc` 和 `u_tpg`，避免手工填写两份互相独立的数字。

数据流如下：

```text
clk、rst_n
    │
    ▼
  u_vtc ── hsync、vsync、de ──► 顶层输出
    │
    └── h_cnt、v_cnt、de ─────► u_tpg ── rgb ──► 顶层输出
pattern_sel ───────────────────► u_tpg
```

顶层只负责配置和连线，不重新实现计数器或颜色判断。

## 编译防护

三个正式设计文件使用：

```verilog
`default_nettype none
```

文件末尾恢复：

```verilog
`default_nettype wire
```

这样拼错端口或内部信号名时会直接编译失败，同时不会影响随后编译的第三方文件。

## 测试设计

实施遵循测试先行：

1. 先新增 `tb_video_top.v` 并尝试编译；由于 `video_top` 尚不存在，测试应按预期失败。
2. 新增最小 `video_top.v`，让测试编译和运行通过。
3. 使用缩小参数检查完整一帧，避免仿真时间过长。
4. 检查四种 `pattern_sel` 的输出、消隐期黑色、同步信号和 `de`。
5. 重新运行已有的 TPG 独立测试与 1080p 完整一帧测试，防止回归。

通过标准：所有 ModelSim 测试均为 0 Errors、0 Warnings，并输出明确的 `TEST_PASS` 信息。

## 文件变更范围

- 新增 `01_design_code/video_top.v`
- 新增 `02_simulation/tb_video_top.v`
- 新增顶层自动检查脚本
- 修改两份现有正式设计文件，仅加入隐式网络防护
- 更新 README、模块说明和结果记录

不修改团队其他成员的算法目录，也不修改团队 `main` 分支。
