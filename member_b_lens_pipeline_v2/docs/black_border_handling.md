# 自动去黑边：有效区域裁剪与一次采样

本次补齐由矫正映射越界造成的黑边处理。默认选择有真实源像素的有效区域，保持比例放大到指定输出尺寸。没有生成额外图像内容，没有先矫正再缩放两次重采样，也不根据 RGB 是否黑色来判断空洞。

## 做法与适用条件

`python/brect/viewport.py` 对原始 H 的每个输出像素分别计算浮点映射和精确的 RTL 定点映射，取两者都落在源图内的严格双线性有效掩码。然后选择整数有效矩形，在其中保持输出比例并留出少量安全边距，把取景变换 V 合成为 `H_effective = H_requested × V`。

矩形搜索不是最终证明：分数坐标、镜头非线性和 H 量化可能让缩放后的坐标与原掩码不同。因此会重新检查最终输出的每个像素，只有浮点和定点映射都没有越界才接受。若仍越界则继续收缩；找不到完整有效区域时明确报错，不默默填黑并宣称完成。没有额外裁剪需求时保留原 H 和全部视野。

取景横纵倍率相同，保持像素比例，输出分辨率不变。会牺牲少量外围视野；源图之外未拍到的真实内容无法靠双线性插值恢复。本版不承诺找到保留视野最多的最优矩形。

## Python 使用

原镜头 CLI 默认启用去黑边：

```sh
PYTHONPATH=python python -B -m brect.lens_cli examples/real_18mm_input.png --calibration calibration/r50_18mm_hdmi_trial.json --output results/lens_autocrop_demo --mode both
```

增加 `--border keep` 可保持原请求的完整视野并允许黑边，方便对照。`--H`、`--size` 仍可用，取景按这次的参数重新计算。低层 `render_lens_float/fixed` API 保持原语义，不会隐式修改 H；需要自动去黑边时先调用：

```python
from brect.viewport import plan_viewport
effective_H, framing = plan_viewport(profile, H=requested_H, output_size=(1920, 1080))
corrected = render_lens_fixed(rgb_image, profile, H=effective_H, output_size=(1920, 1080))
```

`parameters.json` 同时记录请求 H、实际 H、取景缩放、取景矩形、全幅检查数、处理前后的浮点/定点越界计数及试标定状态。批量定点检查逐步遵循已有 Q24 H/Q26 镜头模型；宽乘积可能超过 int64 时使用任意精度中间量，避免验证器自己溢出。

## FPGA 使用

```sh
python -B scripts/export_lens_viewport.py --calibration calibration/r50_18mm_hdmi_trial.json --output-prefix examples/r50_18mm_viewport
```

导出 `.vh` 和 `.json`，一个文件绑定同一套内参、畸变系数、有效 H、源尺寸和输出尺寸。`examples/lens_autocrop_instance.v` 直接使用其中全部常量，不接收外部 H；编译清单为 `examples/autocrop_files.f`。A 的缓存 req/rsp 合同保持不变。

该实例在初始化时由软件自动计算参数，FPGA 逐像素直接使用合成后的 H，无新增每像素裁剪计算或第二次图像插值，取景覆盖最近邻和双线性两种模式。旧 `lens_pipeline_instance` 仍是动态显式 H 的原接口，不会自动获得去黑边保证；使用该入口时须提供为当前几何重新验证的 effective H。

改变焦距、内参、畸变系数、透视 H、源/输出尺寸，都必须重新规划。软件模式自动重算；本版 FPGA 常量模式需要重新导出并综合。未来接入姿态传感器或动态 H 时，需要把取景更新与 H 在帧边界一起提交，该实时控制层尚未实现。本次不增加手动角度输入、纸边识别或黑色角点依赖。

## 当前 18mm 1080p 结果与证据

| 项目 | 处理前 | 自动去黑边后 |
| --- | --- | --- |
| 输出尺寸 | 1920×1080 | 1920×1080 |
| 浮点模型越界位置 | 9,735 | 0 |
| 定点模型越界位置 | 9,735 | 0 |
| 校验范围 | 2,073,600 输出位置 | 2,073,600 输出位置 |

请求 H=单位阵，自动放大约 1.00652985 倍（约放大 0.653%），不改变画面比例。“零越界”衡量映射几何可用性，不是统计黑色像素；棋盘黑格等真实黑色内容会保留。

`scripts/test_viewport.py` 的 7 项检查覆盖：数组定点模型与原标量模型对照（含宽乘积）、无需裁剪的恒等映射、两种采样的真实像素输出、旋转/透视、没有有效区域时拒绝、真实 1080p 全幅检查、CLI 默认/保留模式及硬件导出一致性。

`vectors/lens_autocrop_manifest.json` 保存完整有效性证明。新 RTL 测试比较 13,046 笔事务，包含全部 5,996 个不同边界像素和内部网格，分别验证两种采样、四邻域地址、权重、标签与最终 RGB。全幅逐像素证明来自精确定点模型；RTL 采用这些代表点逐位验证，不能称为全幅板上测试。原 10 项 RTL 回归仍须全部通过。

完整检查入口仍为 `python -B scripts/run_checks.py`，机器报告为 `results/verification.json`，新增边界测试日志为 `results/tb_lens_autocrop.log`。相机参数仍为 `deploy_to_fpga=false` 的试用参数。PDS 综合、资源/Fmax、板上帧率、端到端延迟与光学验收均未因此完成。
