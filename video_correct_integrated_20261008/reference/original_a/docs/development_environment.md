# 开发环境卡片

更新日期：2026-10-05。负责人：A。

## 已确认的开发基准

| 项目 | 内容 | 依据 |
| --- | --- | --- |
| 正式工程根目录 | `C:\D\FPGA\video_correct_fpga` | 用户确认，目录已建立 |
| 学习练习根目录 | `C:\D\FPGA\demo` | 当前 LED、计数器练习位置 |
| 开发板 | MES2L676-100HP | 用户确认 |
| FPGA 完整型号 | PG2L100H-6IFBG676，Logos-2 系列 | 用户确认 |
| PDS 版本 | 2022.2-SP6.4 | 已提供的 PDS 界面截图 |
| 综合引擎 | Pango ADS | 用户约定，计数器已使用 ADS |
| 功能仿真器 | ModelSim SE-64 2020.4 | 已提供的 ModelSim 界面截图 |
| 视频源 | 计划使用佳能 EOS R50，经 HDMI 输入 | 项目计划；尚未确认接入测试结果 |

PDS 的器件选择界面曾显示 `PG2L100H-6FBG676`。记录板卡完整料号时继续使用 `PG2L100H-6IFBG676`。

## 当前正式工程状态

| 项目 | 状态 |
| --- | --- |
| 正式 PDS 工程位置 | `pds/video_correct_top.pds`，逻辑骨架已创建 |
| 正式设计顶层 | `video_correct_top`，逻辑集成层，非板级引脚顶层 |
| 正式仿真顶层 | `tb_video_correct_top`，ModelSim 骨架检查通过 |
| 官方 HDMI 工作例程 | C 已取得匹配例程、未跑通；当前导入代码中未包含底座 |
| 正式引脚与时序约束 | 待从板卡资料和官方例程核实 |

## 待填写的信息

以下项目核实后填写，并注明资料文件或例程位置。

| 项目 | 当前记录 | 主要核实人 |
| --- | --- | --- |
| 板载主时钟名称、频率、引脚 | 待确认 | A/C |
| 复位来源、引脚与有效电平 | 待确认 | A/C |
| LED/按键引脚、有效电平 | 从已成功上板的 LED 工程约束和原理图整理 | A |
| HDMI 输入/输出接口、相关芯片 | 待确认 | C |
| 首版视频分辨率、帧率、像素格式 | 待确认 | A/B/C |
| DDR 存储配置、IP 配置、例程路径 | 待确认 | A/C |
| 下载器、下载接口及 bitstream 配置 | 待从成功上板工程与板卡资料核实 | A/C |
| 正式顶层名称、源文件清单 | 待确认 | A |
| 引脚与时序约束文件名 | 以 PDS 实际工程和官方例程为准 | A/C |
| 编译报告、资源报告、时序报告的实际路径 | 建立正式工程后填写 | A |

## 现有练习验证记录

以下记录来自已提供的工程界面和波形截图，属于 demo 验证。

| 工程/任务 | 已完成内容 | 验证范围 |
| --- | --- | --- |
| LED 常亮与闪烁 | 用户已完成上板演示 | 证明基础建工程、下载及 LED 操作流程可用 |
| `counter_en_rst_demo` | PDS Compile、ADS 综合、Device Map、布局布线、时序报告、bitstream 生成完成 | 当前练习没有添加实际板卡引脚和时钟约束，不能据此认定板级时序合格 |
| `tb_counter_en_rst` | ModelSim 功能仿真运行至 300 ns | 波形验证复位、使能计数、暂停、恢复、再次复位 |

计数器源文件：`C:\D\FPGA\demo\Projects\counter_en_rst_demo\rtl\counter_en_rst.v`。

计数器 testbench：`C:\D\FPGA\demo\Projects\counter_en_rst_demo\sim\tb_counter_en_rst.v`。

计数器 ModelSim 工程目录：`C:\D\FPGA\demo\Simulation\counter_en_rst_sim`。

该 testbench 的时钟周期为 10 ns（100 MHz），它是测试激励设置，不能用作板载时钟频率的依据。HDMI 接入、缓存及矫正功能尚无本次记录中的验证结果。

