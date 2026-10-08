# 成员 C：视频与硬件

正式分支：`main-C`

工程入口：`VideoTimingSim/`

当前成果包含：

- 参数化 1920×1080 视频时序控制器（VTC）
- 竖彩条、纯色、四象限测试图案发生器（TPG）
- 缩小参数教学仿真、TPG 独立检查和完整 1080p 整帧检查
- ModelSim 运行脚本、模块说明与验证日志
- 27 MHz 到 148.5 MHz、10 MHz 的两路 PDS PLL
- MS7210 控制器与 I²C 配置模块
- HDMI 彩条板级顶层、PDS 工程、34 个管脚约束和已生成码流

验证结果：

- TPG 检查：0 Errors，0 Warnings
- 1080p 整帧检查：2,475,000 个像素位置、1,125 行，0 Errors，0 Warnings
- HDMI 板级连接、MS7210 配置与完整硬件源码编译检查：0 Errors，0 Warnings

当前边界：HDMI OUT 工程已经生成码流，但仍需实板彩条验收；HDMI IN、DDR3 帧缓存和算法整合尚未完成。

## 历史管理

成员 C 的 V1–V5 已整合到 `main-C`。后续直接在 `main-C` 保存正式成果，历史变化通过 Git 提交记录查看，不再保留重复的版本分支和标签。
