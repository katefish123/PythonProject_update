# VTC 与 TPG 分模块设计

## 目标

把原先同时产生视频时序和彩条的模块拆成两个职责清楚的模块，使工程结构对应课程的学习顺序：VTC 时序控制器和 TPG 测试图案发生器。

在保留原有视频时序和彩条结果的基础上，让 TPG 能根据水平、垂直坐标产生多种图案，并能独立验证。

## 模块划分

### 1. `video_timing_vtc.v`：VTC 时序控制器

- 输入：`clk`、`rst_n`
- 输出：`h_cnt`、`v_cnt`、`hsync`、`vsync`、`de`
- 职责：计数、判断同步区和有效画面区
- 不再负责产生 RGB 颜色

### 2. `test_pattern_generator_tpg.v`：TPG 测试图案发生器

- 输入：`h_cnt`、`v_cnt`、`de`、`pattern_sel`
- 输出：`rgb`
- 职责：`de=0` 时输出黑色；`de=1` 时根据模式输出竖彩条、纯色或四象限图案

### 3. Testbench：当前阶段的连接位置

- `tb_video_timing.v` 和 `tb_video_timing_1080p.v` 分别实例化 VTC 与 TPG。
- Testbench 把 VTC 的 `h_cnt`、`v_cnt` 和 `de` 连接到 TPG。
- `tb_tpg_patterns.v` 绕过 VTC，直接给 TPG 坐标，独立验证图案逻辑。
- 真正使用开发板时，再增加顶层模块完成相同连接。

## 数据流

`clk/rst_n → video_timing_vtc → h_cnt/v_cnt/de → test_pattern_generator_tpg → rgb`

`video_timing_vtc → hsync/vsync/de → Testbench 观察和检查`

## 验收标准

1. 小参数仿真仍然显示完整的一帧时序和彩条。
2. `de=0` 时 `rgb=24'h000000`。
3. `de=1` 时能按 `pattern_sel` 输出竖彩条、纯色或四象限图案。
4. 正式参数仿真仍检查完整的 1920×1080 有效画面和 2200×1125 总时序。
5. TPG 独立仿真覆盖三种图案与保留模式。
6. ModelSim 编译无错误、无警告。

## 暂不包含

- HDMI 编码和物理接口输出
- FPGA 管脚约束
- 板卡下载验证

这些内容需要后续课程和实际开发板。
