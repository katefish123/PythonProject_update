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
