# A：FPGA 视频矫正集成工程

本分支保存 A 的系统集成工程与个人任务资料，当前同步日期为 2026-10-14。

## 工程入口

- [集成工程与阶段记录](video_correct_integrated_20261008/README.md)
- [当前版本入口](video_correct_integrated_20261008/docs/当前工程入口_20261011.md)
- [旧黑标 DDR 工程](video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/README.md)
- [旧黑标发布文件、源码快照和验证报告](video_correct_integrated_20261008/release/ddr_camera_black_20261014)
- [提速版弃用记录](video_correct_integrated_20261008/docs/版本弃用_黑标提速_20261014.md)
- [本次上传范围](video_correct_integrated_20261008/UPLOAD_SCOPE_20261014.md)

当前阅读与交接以旧黑标 `873cb996` 版为准。提速版按记录弃用，其下载与动态测试入口保持 `.disabled`。本次是文件同步，未重新构建或操作开发板。

## A 个人任务与学习资料

- [资料总览](video_correct_integrated_20261008/A_tasks_20261014/README.md)
- [30 项任务与工程对应表](video_correct_integrated_20261008/A_tasks_20261014/01_A任务与工程对应表.md)
- [30 项逐项讲解](video_correct_integrated_20261008/A_tasks_20261014/02_三十项逐项讲解.md)
- [当前系统接口与数据流程](video_correct_integrated_20261008/A_tasks_20261014/03_当前系统接口与数据流程.md)
- [不用板卡的学习顺序](video_correct_integrated_20261008/A_tasks_20261014/04_不用板卡的学习顺序.md)
- [A 任务资料压缩包](video_correct_integrated_20261008/A_tasks_20261014.zip)

任务包是阅读和交接材料，原始 PDS/ModelSim 工程入口见各版本说明。源码与报告存在不等于全部实板验收完成；固定检测区域、底部灰边、轻微歪斜、真实算法更新率、长期稳定性和任意角度支持仍按各阶段记录核对。外部组件的来源说明保留在工程中。
# FPGA 视频处理三人协作项目

本仓库用于盘古 676 FPGA 视频项目的团队协作。项目目标是先跑通 HDMI 视频链路，再逐步加入图像旋转、插值与任意角度畸变矫正。

## 总体数据链

```text
HDMI 输入
  -> 视频接收 / 解码
  -> RGB 像素流
  -> FPGA 缓存与图像处理
  -> RGB 像素流
  -> HDMI 输出
```

## 三人分工

| 成员 | 主线 | 主要职责 | 阶段交付 |
| --- | --- | --- | --- |
| A | FPGA 主程 / 工程整合 | 顶层设计、模块例化、时钟与复位、RAM/FIFO、综合、时序约束和最终工程 | 可综合顶层、统一接口、缓存验证和构建说明 |
| B | 图像算法 / 硬件化 | Python/OpenCV 正确模型、逆映射、边界处理、插值、定点格式和算法 RTL 验证 | 参考结果、算法公式、定点参数、测试向量和算法模块 |
| C | 视频链路 / 板卡联调 | VTC、TPG、视频时序、HDMI IN/OUT、RGB 像素流、透传和板卡调试 | 视频时序模块、测试图案、ModelSim 验证、HDMI 例程和联调记录 |

> B 不只是编写 Python，后期还要参与定点化和算法 RTL 验证；C 也不是把 B 的 Python 逐行翻译成 Verilog。A 负责把各模块连接成可运行工程。

## 仓库导航

| 路径 | 内容 |
| --- | --- |
| [`v1/`](v1/) | Python/OpenCV 图像旋转初版，采用最近邻取样 |
| [`v2/`](v2/) | 加入双线性插值、输入校验和更完整的文件处理 |
| [`v3/`](v3/) | 使用 Q1.16 定点系数，向 FPGA 硬件实现靠拢 |
| [`member_c/`](member_c/) | 成员 C 的视频与硬件成果 |
| [`member_c/VideoTimingSim/`](member_c/VideoTimingSim/) | VTC、TPG、正式顶层及 ModelSim 仿真工程 |
| [`docs/`](docs/) | 已确认的设计说明和协作资料 |
| [`docs/git提交规范.md`](docs/git提交规范.md) | 提交身份、本机配置、历史改写与分支合并规则 |

成员 C 的工程使用说明见 [`member_c/VideoTimingSim/README.md`](member_c/VideoTimingSim/README.md)。

## 成员 C 正式成果

成员 C 的正式交付统一维护在 [`main-C`](https://github.com/katefish123/PythonProject_update/tree/main-C)。旧的 V1–V5 临时分支和标签已完成整合，不再作为独立入口保留；历史变化仍可通过 `main-C` 的提交记录查看。

## 当前验证结果

成员 C 的 V5 延续以下 ModelSim 检查：

- TPG 三种图案自动检查：`0 Errors, 0 Warnings`
- 1920x1080 完整时序检查：2,475,000 个像素位置、1,125 行，`0 Errors, 0 Warnings`
- VTC + TPG 顶层联调检查：`0 Errors, 0 Warnings`
- HDMI 板级连接检查：`TEST_PASS_HDMI_TOP`，`0 Errors, 0 Warnings`
- PDS 生成的 148.5 MHz 与 10 MHz PLL 自带 Testbench：均为 `Simulation Success`，`0 Errors, 0 Warnings`

V5已加入来源明确的真实MS7210控制器和I²C驱动；真实总线仿真及完整硬件顶层编译载入通过。正式PDS工程在 `member_c/VideoTimingSim/05_pds/VideoTimingSim_V5.pds`，34个管脚按官方手册核对。PDS编译、综合、布局布线、内部时序与码流生成通过，视频内部建立WNS为4.475ns。报告与3791112字节sbit见 `member_c/VideoTimingSim/04_results/pds_v5/`。MS7210外部接口时序、复位/I²C行为复核和实板彩条验收仍未完成。

## 联调前必须统一

三条路线合并前，需要共同确认：

- 分辨率与帧率
- RGB / YUV 格式及各通道位宽
- `pixel_clk` 频率
- `hsync`、`vsync` 的有效极性
- `de` 有效区定义
- 坐标原点、横纵方向和边界规则
- 定点数 Q 格式、取整和溢出规则
- 帧开始、行开始及模块握手方式

## GitHub 协作规则

1. 每位成员在自己的正式分支和目录中提交：A 使用 `main-A`，B 使用 `main-B`，C 使用 `main-C`；提交信息带成员或模块名称。
2. 阶段历史通过正式分支的提交记录保存，不再额外建立成员版本分支或版本标签。
3. 合并到团队 `main` 前先由另外一名成员检查接口、测试结果和文件归属。
4. 不提交 ModelSim `work*`、临时波形、崩溃记录或编辑器缓存。
5. 每次联调记录使用的分支、标签、分辨率、时钟和接口版本，避免三个人测试不同代码。

## 当前下一步

- A：确认顶层与缓存接口骨架。
- B：提供软件参考结果、坐标映射公式和定点约定。
- C：使用V5 PDS工程与实验码流，先复核外部接口时序、初始化和复位/I²C行为，完成显示器彩条验收，再推进HDMI IN与视频透传。
