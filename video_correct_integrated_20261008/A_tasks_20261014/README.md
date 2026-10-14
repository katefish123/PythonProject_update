# A 个人任务整理

你的主责是把 C 的视频底座、B 的算法和帧缓存组织成一个可验证的系统，并维护接口、时钟复位、工程与版本。这里按原清单整理了25项主任务和5项补充任务，每项都有对应代码或明确的待补内容。

本资料以旧黑标版873cb996为准。提速39574d43版已经被用户弃用，不进入本包。板卡已交给队友，本轮没有上板操作。代码存在或测试通过，不等于你本人已经理解；讲解里的自检用于学习，不能代替工程验收。

## 从这里开始

- [先看30项任务分别对应哪些文件](<C:/D/FPGA/video_correct_integrated_20261008/A_tasks_20261014/01_A任务与工程对应表.md>)
- [每项是什么 已有什么 还要补什么](<C:/D/FPGA/video_correct_integrated_20261008/A_tasks_20261014/02_三十项逐项讲解.md>)
- [完整数据流 时钟 地址 请求响应和状态机](<C:/D/FPGA/video_correct_integrated_20261008/A_tasks_20261014/03_当前系统接口与数据流程.md>)
- [先基础实验 再读整机 六步学习路线](<C:/D/FPGA/video_correct_integrated_20261008/A_tasks_20261014/04_不用板卡的学习顺序.md>)
- [A B C边界 当前缺口和版本交接](<C:/D/FPGA/video_correct_integrated_20261008/A_tasks_20261014/05_A与队友交接清单.md>)
- [点击跳到复制代码及实际编译源文件](<C:/D/FPGA/video_correct_integrated_20261008/A_tasks_20261014/06_代码入口索引.md>)
- [对照原PDF查看各阶段A要交付什么](<C:/D/FPGA/video_correct_integrated_20261008/A_tasks_20261014/07_按原计划的A交付节点.md>)

## 文件夹用途

| 文件夹 | 内容 |
|---|---|
| 00_requirements | 原PDF分工文件和原A任务清单 原件未修改 |
| 01_basics | 已有FIFO RAM和计数器练习 真实IP配置 TB 日志和截图 |
| 02_system | 从旧版冻结源码提取的A集成模块 不是按同名文件猜选 |
| 03_partner_reference | B算法合同和关键模块 C及厂商底座接口 |
| 04_reference_docs | 历史接口 DDR参数和来源材料 |
| 05_verification | 旧版TB 构建脚本 封存源快照和验证证据 |
| 06_handoff | 旧版恢复入口文本和提速版撤下说明 |

## 阅读与运行边界

本包是阅读和交接资料，未配置为新的独立PDS工作目录。需要运行仿真或构建时，使用索引中列出的原工程入口；学习副本不替代原工程依赖和源清单。没有加入任何自动上板操作。

正式目录video_correct_fpga保留早期骨架和接口资料。实际旧黑标工程在video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014。多个同名.v文件是不同阶段的实现，务必按build.tcl和source_hashes确定实际编译源。

旧版已有完整RGB仿真对照、最终时序、下载回读和短时实拍出图记录；底部灰边、轻微歪斜、真实算法更新率、长期稳定性和任意角度仍不能称为完成。
