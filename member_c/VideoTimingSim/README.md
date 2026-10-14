# VideoTimingSim

> 最新 C 接续：[完整 1920×1080 源图与竖向校正](../IntegratedBaseline/fullhd_source_20261013/README.md)。请从这里查看本轮实现、复现方法和未完成项。

> 当前集成主线以 [A完整工程同步基线](../IntegratedBaseline/a_sync_20261013/README.md) 为准。A 已有异步 FIFO、完整源采集、写入排空、算法调度和结果双缓冲；下文新增三源槽等模块保留为候选扩展，不作为当前必须替换的主线。

> 2026-10-13 后续：统一内存布局组件、完整源确认与 DDR 应答合并、三帧槽发布流程已接好并通过仿真。接入 A 板级工程的边界见 [DDR地址分区与完整帧发布](03_documents/DDR地址分区与完整帧发布_20261013.md)。

> 2026-10-13：已同步 A 完整工程与 B 黑色角标增量；新增 RGB 块流到 A DDR 命令口的写入适配，仿真通过。地址分区冲突、集成条件和验收范围见 [GitHub同步与DDR写入适配](03_documents/GitHub同步与DDR写入适配_20261013.md)。

> 2026-10-08 C 相机链路交接：最新现场基线是 `hdmi_camera_loop_top` 的 RGB888 全分辨率、接收端优先版本。源码快照、复现入口和验收边界见 [C相机链路交接](03_documents/C相机链路交接_20261008.md)。原 V5 彩条工程保留独立入口；本增量需要仓库外的 RX 依赖，不能仅据仿真或下载成功宣称端到端验收。

当前版本：**V5：真实 MS7210 与 I²C 配置模块整合**（2026-10-05）。

先看 `03_documents/V5整合说明与缺项清单.md`。正式硬件源码清单为 `hardware_sources.f`，板级顶层为 `hdmi_colorbar_top`。PDS工程在 `05_pds/VideoTimingSim_V5.pds`；已生成HDMI OUT实验码流，尚未上板验收。

这是视频时序模块的 Verilog 学习与仿真工程。工程使用 VS Code 编辑代码，使用 ModelSim 编译、自动检查和查看波形。

## 当前成果

- `video_timing_vtc.v`：VTC 时序控制器，默认生成 1920x1080@60 的计数、同步和有效区信号。
- `test_pattern_generator_tpg.v`：TPG 测试图案发生器，可选择竖彩条、纯色和四象限图案。
- `video_top.v`：正式可综合顶层，统一参数并连接 VTC 与 TPG。
- `hdmi_colorbar_top.v`：MES2L676-100HP 板级连接顶层，把两路 PLL、视频核心和 MS7210 配置接口连接起来。
- `ms7210_config.v`：连接 MS7210 寄存器控制器与 I2C 驱动的配置层。
- `01_design_code/third_party/ms7210`：V5 接入的真实寄存器控制器、I²C驱动、上游许可证和来源说明；这些模块来自第三方参考工程。
- `01_design_code/ip`：PDS 生成的两个 Logos2 GPLL，分别完成 27 MHz→148.5 MHz 和 27 MHz→10 MHz。
- `tb_video_timing.v`：14x7 缩小版教学仿真，用于看清计数、同步、`de` 和 RGB 彩条。
- `tb_video_timing_1080p.v`：正式参数仿真，自动检查完整一帧的 2475000 个像素位置。
- `tb_tpg_patterns.v`：不依赖 VTC 的 TPG 独立测试，逐项检查三种图案。
- `tb_video_top.v`：检查正式顶层的参数传递、模块连接和完整一帧输出。
- `tb_hdmi_colorbar_top.v`：使用仿真 PLL 和 MS7210 模型检查板级连线、复位释放和第一段彩条。
- `tb_ms7210_config.v`：通过真实控制器/驱动和外部I²C设备模型，检查缺设备、校验读回、配置传输与复位。
- V5 本轮六项检查通过：真实I²C、真实硬件顶层编译载入、TPG、视频顶层、1080p一帧与原HDMI行为测试，均为0错误、0警告。证明范围见结果说明，不能替代上板验收。

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
10. 检查真实MS7210配置：执行 `vsim -c -do run_ms7210_check.do`。
11. 检查完整真实硬件源码：执行 `vsim -c -do run_hdmi_real_compile.do`，只编译与载入，不运行端到端视频测试。更换PDS安装位置时，设置环境变量 `PDS_SIM_GPLL` 指向该版本的 `GTP_GPLL.v` 仿真文件。

## 目录说明

| 名称 | 用途 |
| --- | --- |
| `01_design_code` | FPGA 最终实现的正式 Verilog 设计代码 |
| `01_design_code/ip` | PDS 生成的 PLL 配置、Verilog、模板和自带 Testbench |
| `01_design_code/third_party` | 第三方模块，保留作者、许可证与来源记录 |
| `02_simulation` | 仅用于电脑仿真的Testbench与外部设备模型 |
| `03_documents` | 模块接口、时序参数和仿真操作说明 |
| `04_results` | ModelSim日志及PDS V5报告、码流与校验摘要 |
| `05_pds` | 可打开的PDS工程、相对路径构建脚本和FDC约束 |
| `work*` | ModelSim 自动生成的本地编译缓存，不放入分享包 |
| `VideoTimingSim.mpf` | ModelSim 工程入口 |

## 当前边界

V5 已补入真实MS7210控制器和I²C驱动，完成真实总线仿真及包括两路PLL的完整模块编译载入。两路PLL针对 `PG2L100H / -6 / FBG676` 生成；完整型号中的 `I` 表示工业温度等级。已补齐正式PDS工程、34个引脚约束和27MHz输入约束，真实PLL自动推导两路时钟，完成综合、布局布线、内部时序检查和码流生成。仍缺MS7210外部接口时序、复位/I²C电气及错误处理复核、寄存器格式验证和上板画面验收。相机HDMI输入、DDR帧缓存和算法还需后续集成。

`tb_hdmi_colorbar_top.v` 内含与真实模块同名的行为替身，只由其专用脚本编译；不要把它加入 `hardware_sources.f` 或与第三方驱动混编。VS Code索引使用真实模块，ModelSim工程已登记新文件。

## 分享注意事项

分享时保留README、运行脚本、`hardware_sources.f`、ModelSim工程和五个编号目录，尤其保留第三方的LICENSE与SOURCE.md；排除 `work*` 编译缓存、备份、崩溃记录和WLF文件。工程源文件使用相对路径。对外发布前核对第三方原始授权范围；正式成果统一维护在团队仓库的 `main-C` 分支。

## PDS V5补充

打开 `05_pds/VideoTimingSim_V5.pds`；构建、管脚和上板步骤见 `05_pds/README.md`。完整流程已通过，视频内部建立余量4.475ns；MS7210外部接口时序和实板画面尚未验收。下载文件与原始报告见 `04_results/pds_v5`。相关源码、PDS补充和验证记录均已归档在 `main-C`。
