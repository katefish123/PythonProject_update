# MES2L676-100HP HDMI 彩条输出接入设计

日期：2026-10-04

## 本阶段目标

让现有的 `video_timing_vtc.v` 和 `test_pattern_generator_tpg.v` 从“只能在 ModelSim 中观察”前进到“具备接入真实开发板 HDMI OUT 的清晰接口”。

本阶段固定输出 1920×1080、60 Hz 彩条，不实现动态分辨率切换，也不加入 HDMI 输入和 DDR。

## 已确认的硬件

- FPGA 完整订货型号：PG2L100H-6IFBG676（以 MES2L676-100HP 官方硬件手册为准）。
- 型号中的 `-6` 是速度等级，`I` 是工业温度等级，`FBG676` 是封装。
- PDS 将这些字段分开选择，因此工程设置应填写：器件 `PG2L100H`、速度等级 `-6`、封装 `FBG676`。PDS 中不显示字母 `I` 是正常的，不代表选错芯片。
- 板载参考时钟：27 MHz。
- HDMI OUT 芯片：MS7210，I2C 设备地址为 0xB2。
- 1080p60 像素时钟：148.5 MHz。
- MS7210 配置时钟：10 MHz。

## 模块连接

```text
27 MHz 板载时钟
    ├── video_pll_27m_148m5 ── 148.5 MHz ── video_top(VTC + TPG)
    │                                            │
    │                                            └── RGB/HS/VS/DE/PCLK ── MS7210
    │
    └── config_pll_27m_10m ── 10 MHz ── ms7210_config ── I2C ── MS7210
```

## 文件职责

- `01_design_code/hdmi_colorbar_top.v`
  - 真实开发板的顶层连接文件。
  - 连接两个 PLL、现有 `video_top` 和 MS7210 配置模块。
  - 默认让 TPG 输出竖向彩条。
- `01_design_code/ms7210_config.v`
  - 连接 MS7210 寄存器控制器与通用 I2C 驱动。
  - 不在这里重复或伪造 MS7210 寄存器表。
- `01_design_code/ip/video_pll_27m_148m5/`
  - PDS 2022.2-SP6.4 生成的 Logos2 GPLL。
  - 输入 27 MHz，`clkout0` 输出 148.5 MHz，供 1080p60 像素扫描使用。
- `01_design_code/ip/config_pll_27m_10m/`
  - PDS 2022.2-SP6.4 生成的 Logos2 GPLL。
  - 输入 27 MHz，`clkout0` 输出 10 MHz，供 MS7210 配置逻辑使用。
- `02_simulation/tb_hdmi_colorbar_top.v`
  - 用很小的画面参数验证顶层连线、复位释放和第一段彩条。
  - PLL 和 MS7210 控制器在测试中使用行为模型，真实硬件仍必须使用 PDS IP 与有授权的官方源码。
- `run_hdmi_board_check.do`
  - 一键执行上述板级连接测试。

## 明确不复制的内容

V4之前找到的Sparrow参考仓库未发现许可证，继续仅用于参考。V5另从声明MIT的 `whu-gyn-2006/fpga-defect-sorting-system` 导入MS7210与I²C模块，原始署名及许可证保存在 `01_design_code/third_party/ms7210`。源码未修改逻辑；来源和限制详见其中SOURCE.md。

此外，另一个公开工程的 PLL 面向 PGL50H、50 MHz 输入，不适用于本板的 PG2L100H、27 MHz 输入。

## PLL 生成结果

两个 PLL 均由 PDS 自带的 IP Generator 生成，器件为 `PG2L100H / -6 / FBG676`，模式为 Logos2 GPLL，端口均为 `clkin1`、`clkout0` 和 `lock`。

| 模块 | 输入 | 输出 | VCO | 关键分频参数 |
| --- | ---: | ---: | ---: | --- |
| `video_pll_27m_148m5` | 27 MHz | 148.5 MHz | 742.5 MHz | IDIV=1，MDIV=2，FDIV=13.75，ODIV0=5 |
| `config_pll_27m_10m` | 27 MHz | 10 MHz | 1147.5 MHz | IDIV=1，MDIV=2，FDIV=21.25，ODIV0=114.75 |

两次 PDS 生成均为 0 Errors、0 Warnings；生成后的 Verilog 与 PDS 官方 `GTP_GPLL` 仿真模型在 ModelSim 中编译为 0 Errors、0 Warnings，两个 PDS 自动生成的 Testbench 也都显示 `Simulation Success`。

## 进入真实上板前仍需补齐

1. V5已补入MS7210和I²C实现。上板前复核寄存器RGB格式、I²C应答及电气行为，并核对第三方原始授权。
2. PDS工程已建立于 `05_pds/VideoTimingSim_V5.pds`，包含9个真实设计源文件与两路PLL Verilog。
3. FDC已覆盖34个端口并与官方手册、PCF和布线IO表核对；MS7210外部接口延迟还需补齐。
4. PDS综合、布局布线、内部时序与码流生成已完成；下载和显示器彩条验收尚未进行。

V5的本轮结果与完整分工缺项，以 `V5整合说明与缺项清单.md` 为准；新增真实I²C测试不使用旧板级Testbench中的同名替身。
