# B 成员算法工程 V2：真实标定参数与镜头畸变校正

本版增加 **标定 JSON → 二阶径向/切向畸变映射 → 缓存读取 → 双线性插值**，可与显式透视 H 组合，只对原始图像采样一次。新入口 `examples/lens_pipeline_instance.v` **不依赖四色或四个黑色角点**。Python 提供浮点/位精确定点参考，RTL 提供逐拍坐标流水。

2026-10-22 补充：镜头 CLI 默认自动裁剪有效区域并等比例放大，消除映射越界黑边。FPGA 对应入口为 `examples/lens_autocrop_instance.v`，使用同一份导出的内参和有效 H。方法、视野损失与适用条件见 `docs/black_border_handling.md`。旧动态 H 入口仍保留原边界行为。

当前使用佳能 R50、18mm、实际 HDMI 1920×1080 的试标定参数；`deploy_to_fpga=false` 与适用条件均保留。这表示可做算法试算，最终光学参数尚需独立固定焦距/对焦验证。

## 先看结果

- `results/lens_autocrop_demo/preview.jpg`：去黑边前后与定点结果，当前 1080p 全幅浮点/定点均为零越界。

- `results/lens_demo/preview.jpg`：真实 1080p 棋盘原图、浮点、定点输出对照。
- `results/lens_demo/parameters.json`：实际参数及数值对照，本例全图 RGB 单通道最大差为 1。
- `docs/validation_lens_v2.md`：验证范围及剩余目标。
- `docs/integration_lens_v2.md`：Python 命令、H 方向、RTL 接线、缓存约定。

预览默认请求 H=单位阵，CLI 再自动规划去黑边的有效 H；棋盘的拍摄透视仍保留，当前未加入自动纸边检测。`results/lens_demo` 保留历史未裁剪结果。

## 运行检查与示例

Python 3.10+、NumPy、Pillow；RTL 检查需要 PATH 内有 Icarus 的 `iverilog` 和 `vvp`。新 Python 检查还使用 OpenCV 作为独立数值对照。

```sh
python -m pip install -r requirements.txt
python -m pip install opencv-python
python -B scripts/run_checks.py
```

只有 Python 检查、十一项 RTL 仿真和实际 RTL 输出对比均通过才打印 `ALL_CHECKS_PASS`。完整检查需要 OpenCV 独立对照，缺少该依赖会失败并提示安装，不会把跳过当作通过。`results/verification.json` 和日志记录证据。`--python-only` 明确跳过 RTL，不代表硬件算法已验证。Windows 可运行 `run_checks.bat`。

macOS/Linux 运行真实图示例：

```sh
PYTHONPATH=python python -B -m brect.lens_cli examples/real_18mm_input.png --calibration calibration/r50_18mm_hdmi_trial.json --output results/lens_autocrop_demo --mode both
```

Windows CMD 先 `set PYTHONPATH=python`，再运行同一条 `python -B -m ...`。默认双线性、请求 H=单位阵并自动规划有效 H；`--method nearest` 切最近邻。增加 `--border keep` 可复现历史未裁剪视野，允许越界填黑；请另设输出目录以保留现有对照。只做快速浮点预览用 `--mode float`；逐像素定点是正确性参考，不承诺电脑实时帧率。

ModelSim/Questa 可在包根目录执行 `do run_modelsim.do`，脚本共十一项，全部通过才显示 `ALL_MODELSIM_CHECKS_PASS`。本机本次证据来自 Icarus；没有本版 ModelSim 原生全套实跑凭据。

## 本次主要文件

| 文件 | 用途 |
| --- | --- |
| `calibration/r50_18mm_hdmi_trial.json` | 真实 HDMI 内参、k1/k2/p1/p2 与试用元数据 |
| `python/brect/calibration.py` | 严格读取/校验参数，导出定点常量 |
| `python/brect/lens.py`、`lens_cli.py` | 无标记的 H+镜头组合映射与一次重采样 |
| `scripts/export_calibration.py` | JSON → `.vh` 与硬件元数据 JSON |
| `rtl/lens_distort_coord.v` | 10 个寄存级，II=1 的二阶径向/切向坐标计算 |
| `rtl/perspective_core.v` | 可选镜头级、带符号越界检查与原插值连接 |
| `examples/lens_pipeline_instance.v`、`lens_files.f` | 启用 1080p 试标定的新实例和编译清单 |
| `scripts/test_lens.py`、`generate_lens_vectors.py` | 独立模型检查与定点测试向量 |
| `sim/tb_lens_distort_coord.sv`、`tb_lens_integration.sv` | 530 组坐标、835 组组合缓存/插值事务 |
| `docs/lens_numeric_contract.md` | 位宽、逐步移位、旁路、错误和坐标合同 |

`perspective_core` 默认 `LENS_ENABLE=0`，兼容旧入口。旧标记演示及其八项回归保留，旧用法见 `README_legacy_v1.md`；它不能作为无标记纸张识别的完成证据。

## 交付边界

本版完成镜头校正的软件与 RTL 算法验证。**自动识别无标记纸边、上位机角度协议/姿态控制层尚未实现**；新入口目前接收调用方提供的 H，帧内应保持稳定。

尚未将本版接入 A/C 的最新完整演示工程，未进行 PDS 综合、资源/Fmax、上板帧率或端到端延迟测量，也未完成赛事光学指标验收。II=1 是算法接口的仿真属性，整机性能仍取决于时序和缓存带宽。
