# VideoTimingSim

这是视频时序模块的 Verilog 学习与仿真工程。工程使用 VS Code 编辑代码，使用 ModelSim 编译、自动检查和查看波形。

## 当前成果

- `video_timing_vtc.v`：VTC 时序控制器，默认生成 1920x1080@60 的计数、同步和有效区信号。
- `test_pattern_generator_tpg.v`：TPG 测试图案发生器，可选择竖彩条、纯色和四象限图案。
- `video_top.v`：正式可综合顶层，统一参数并连接 VTC 与 TPG。
- `hdmi_colorbar_top.v`：MES2L676-100HP 板级连接顶层，把两路 PLL、视频核心和 MS7210 配置接口连接起来。
- `ms7210_config.v`：连接 MS7210 寄存器控制器与 I2C 驱动的配置层。
- `01_design_code/ip`：PDS 生成的两个 Logos2 GPLL，分别完成 27 MHz→148.5 MHz 和 27 MHz→10 MHz。
- `tb_video_timing.v`：14x7 缩小版教学仿真，用于看清计数、同步、`de` 和 RGB 彩条。
- `tb_video_timing_1080p.v`：正式参数仿真，自动检查完整一帧的 2475000 个像素位置。
- `tb_tpg_patterns.v`：不依赖 VTC 的 TPG 独立测试，逐项检查三种图案。
- `tb_video_top.v`：检查正式顶层的参数传递、模块连接和完整一帧输出。
- `tb_hdmi_colorbar_top.v`：使用仿真 PLL 和 MS7210 模型检查板级连线、复位释放和第一段彩条。
- 五组仿真均已通过，编译为 0 错误、0 警告。

## 从哪里开始

1. 阅读 VTC：打开 `01_design_code/video_timing_vtc.v`。
2. 阅读 TPG：打开 `01_design_code/test_pattern_generator_tpg.v`。
3. 阅读正式连接：打开 `01_design_code/video_top.v`。
4. 查看教学波形：使用 ModelSim 执行根目录的 `run_wave.do`。
5. 检查正式顶层：在工程根目录执行 `vsim -c -do run_top_check.do`。
6. 独立检查 TPG：在工程根目录执行 `vsim -c -do run_tpg_check.do`。
7. 运行正式 1080p 检查：在工程根目录执行 `vsim -c -do run_1080p_check.do`。
8. 检查 HDMI 板级连线：在工程根目录执行 `vsim -c -do run_hdmi_board_check.do`。
9. 查看结果：打开 `04_results/README.md` 和对应的检查日志。

## 目录说明

| 名称 | 用途 |
| --- | --- |
| `01_design_code` | FPGA 最终实现的正式 Verilog 设计代码 |
| `01_design_code/ip` | PDS 生成的 PLL 配置、Verilog、模板和自带 Testbench |
| `02_simulation` | 五份仅用于电脑仿真的 Testbench |
| `03_documents` | 模块接口、时序参数和仿真操作说明 |
| `04_results` | 已验证的测试结论和 ModelSim 日志 |
| `work*` | ModelSim 自动生成的本地编译缓存，不放入分享包 |
| `VideoTimingSim.mpf` | ModelSim 工程入口 |

## 当前边界

本阶段已经完成 VTC、TPG、视频顶层、HDMI 板级连接层以及两路 PDS PLL。板级连接已通过行为仿真，两路 PLL 已由 PDS 针对 `PG2L100H / -6 / FBG676` 生成并通过其自带 Testbench；真实上板仍需加入来源明确的官方 MS7210 控制器、I2C 驱动、正式 PDS 工程和 FDC 管脚约束。完整订货型号中的 `I` 表示工业温度等级，PDS 不把它写进封装名称。相机输入仍不在本阶段内。

## 分享注意事项

分享时保留 README、四份运行脚本、ModelSim 工程和四个编号目录；排除 `work*` 编译缓存、`.bak` 备份文件、`.cr.mti` 崩溃记录和临时 WLF 文件。工程源文件使用相对路径，同伴无需使用与你相同的磁盘目录。
