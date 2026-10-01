# 仿真结果

## 1080p60 正式参数检查

- 检查日期：2026-09-30
- 总时序：2200 x 1125
- 有效画面：1920 x 1080
- 检查像素位置：2475000
- 检查行数：1125
- 编译结果：0 Errors，0 Warnings
- 仿真结论：`TEST_PASS_1080P`
- 模块结构：独立 VTC `video_timing_vtc` + 独立 TPG `test_pattern_generator_tpg`

详细 ModelSim 输出见 `1080p_check.log`。

## 教学仿真

- 缩小时序：14 x 7
- 检查内容：计数器、同步信号、有效区、红绿蓝白彩条、整帧回绕
- 仿真结论：`TEST_PASS: complete video timing and RGB output are correct`

## TPG 独立仿真

- 检查内容：消隐区、竖彩条、纯色、四象限和保留模式
- 仿真结论：`TEST_PASS_TPG: all pattern modes are correct`
- 详细输出：`tpg_check.log`
