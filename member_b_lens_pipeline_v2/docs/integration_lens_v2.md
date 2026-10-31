# 镜头校正 V2 接入说明

本阶段把真实 HDMI 标定参数接入已有坐标和插值链路。新入口为 `examples/lens_pipeline_instance.v`，输入显式 H，不运行四色或四个黑色角点检测。旧 `b_rectifier` 和旧 CLI 保留用于兼容回归；旧版说明见 `README_legacy_v1.md`，其中标记要求不适用于新入口。

## 数据方向与一次重采样

```text
输出像素 (x,y)
    ↓ 目标 → 理想源平面的 H（逆透视）
理想源坐标 (u,v)
    ↓ K 与 k1,k2,p1,p2 的 Brown 正向畸变公式
原始相机画面采样坐标 (sx,sy)
    ↓ 四邻域缓存读取 → 双线性插值
输出 RGB
```

畸变公式使用正向模型，是因为每个输出像素需要反查原始畸变图上的采样位置。无需先生成一张去畸变中间图再做透视，源图只重采样一次。H=单位阵时仅做镜头校正。

**H 必须映射到去畸变的理想像素平面。** 从原始畸变画面检测到的纸角不能直接代入 H 求解器；需要先将这些点去畸变。自动纸边检测及其点坐标转换还未接入本版。上位机可向此入口提供 H，但角度指令协议、接收模块和由姿态生成 H 的控制层尚未实现。

## Python 参数与图像

在包根目录运行：

```sh
PYTHONPATH=python python -B -m brect.lens_cli examples/real_18mm_input.png --calibration calibration/r50_18mm_hdmi_trial.json --output results/lens_autocrop_demo --mode both
```

Windows CMD 先运行 `set PYTHONPATH=python`，再执行同一条 `python -B -m ...` 命令。默认输出 1920×1080、双线性、请求 H=单位阵；CLI 自动裁剪有效区域并等比例放大，实际使用自动规划的有效 H，生成 `float.png`、`fixed.png`、`parameters.json`。增加 `--border keep` 可复现历史未裁剪视野并允许越界填黑；请另设输出目录，`results/lens_demo` 保留历史结果。定点逐像素参考运行较慢，不用于测电脑实时性能。只预览浮点可用 `--mode float`。

组合透视时增加 `--H my_h.json --size 1280 720`。JSON 为 3×3 数组或 `{"H": [[...], [...], [...]]}`，方向为“输出像素 → 理想源像素”。`--method nearest` 可切最近邻。源图尺寸必须与标定文件相同，程序拒绝隐式缩放、裁剪和 EXIF 自动旋转。

```python
from brect.calibration import load_calibration
from brect.lens import render_lens_float, render_lens_fixed

profile = load_calibration("calibration/r50_18mm_hdmi_trial.json", (1920, 1080))
result = render_lens_float(rgb_uint8, profile)  # 单位 H，仅去畸变
```

上述低层渲染 API 不隐式规划取景。需要软件自动去黑边或绑定参数的静态 FPGA 入口 `examples/lens_autocrop_instance.v` 时，见 `docs/black_border_handling.md`；其中说明有效 H 导出及几何变化后重新规划的要求。

解析器检查 K、冗余的 fx/fy/cx/cy、畸变向量的一致性、有限数值、尺寸、正焦距和 k3=0。本阶段支持四项 `k1,k2,p1,p2`，不接受非零 k3、非零 skew 或其他镜头模型。固定参数导出保留标定的试用状态与适用条件。

## RTL 接线

将 `examples/lens_files.f` 中的源文件及新示例加入算法工程，编译工作目录设为包根目录，使 `examples/r50_18mm_calibration.vh` 可被找到。只检查端口和语法可运行：

```sh
iverilog -g2005 -Wall -s lens_pipeline_instance -o /tmp/lens_example.vvp -f examples/lens_files.f
```

也可直接实例化 `perspective_core`，设置 `SRC_W=1920`、`SRC_H=1080`、`LENS_ENABLE=1` 及十项 `LENS_*` 参数。默认 `LENS_ENABLE=0` 保留旧路径。该示例不是板级顶层，不带 HDMI、DDR 或跨时钟域。

| 信号 | A/C 与 B 之间的约定 |
| --- | --- |
| `clk,rst_n` | 全链同一处理时钟域；低有效复位 |
| `in_valid,dst_x,dst_y` | 每拍可接收一个输出像素请求，无反压；上层必须保证缓存吞吐能力 |
| `h00..h22` | signed40 / 24 位小数；一帧内稳定，或由调用方在帧边界原子提交 |
| `geometry_valid` | H 是否可用；无效请求仍按序填黑返回 |
| `nearest` | 每请求选择最近邻或双线性，元数据随流水线同步 |
| `req_valid,req_tag,addr00..11,req_fx,req_fy` | 给缓存的地址与目的像素标签、分数权重 |
| `req_inside,req_error` | 前者表示可读源图；后者表示数值映射错误；画面外正常坐标只清 inside |
| `rsp_valid,rsp_tag,rsp_inside,rsp_fx,rsp_fy,p00..11` | 每个 req 必须恰好响应一次，严格保持请求顺序；标签、权重和 inside 必须原样带回 |
| `out_valid,out_tag,out_rgb` | 插值输出；inside=false 或数值错误请求填黑 |

缓存响应延迟允许变化，但 B 没有乱序重排或背压。复位时 A 必须同时清空待处理请求、响应和队列，避免旧响应进入复位后的 B。

新增镜头叶模块有 10 个寄存级，输入采样边沿 E0 到输出边沿 E9，相隔 9 个时钟周期；II=1。正常、旁路和错误路径延迟相同。开启该级会增加请求到达缓存前的延迟；外部不能继续假定旧版固定等待周期，应按 valid/tag 接口工作。端到端延迟仍取决于 H 除法流水、缓存响应与插值，不用该叶模块周期数推算整机帧率。

## 参数导出与边界

```sh
python -B scripts/export_calibration.py --calibration calibration/r50_18mm_hdmi_trial.json --output-prefix examples/r50_18mm_calibration
```

导出 `.vh` 与 `.hardware.json`，后者包含试用状态。修改 JSON 后必须重新导出、重新仿真和综合；FPGA 不会直接读取磁盘 JSON，也没有新增运行时串口参数下载。

H 保留已有 UQ12.8 理想坐标域 0..4095+255/256；H 阶段的负坐标或过小分母会被拒绝。镜头阶段保留 signed40 Q8，可表示的负采样坐标属于画面外而非数值错误；归一化坐标任一绝对值超过 2 时数值拒绝。双线性严格检查原始图边界，在末行末列钳位上邻域；画面外填黑。完整位宽、移位顺序及地址规则见 `docs/lens_numeric_contract.md`。

当前 18mm 试标定可供算法试算，`deploy_to_fpga=false`。板上最终参数仍须在固定焦距、确定对焦及相机处理设置后，使用独立 HDMI 采集补验边缘效果。现有数据不能据此判定光学指标达标。
