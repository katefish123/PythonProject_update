# B 成员：黑色四角标记与实时透视矫正

本工程从源图中检测 **4 个黑色标记**，按左上、右上、右下、左下的顺序求四角，再计算逆透视矩阵 H，对输出像素做最近邻或双线性采样。四角的身份由各自的搜索区域（ROI）确定。输入和矫正后的图像仍为 **RGB888 彩色图像**；“改为黑色”指角点标记的检测规则。

工程包含 Python 数值参考、可综合的 Verilog 算法模块、自动化回归、合成演示和 A/C 接口资料。B 包负责检测与透视算法；A 负责帧缓存、DDR、请求调度和跨时钟域，C 负责显示时序、HDMI 和 PLL。本目录没有可直接下载的完整板级顶层。

## 先找到需要的文件

| 目录/入口 | 应在什么情况下打开 |
| --- | --- |
| [python/brect/](python/brect/) | 用电脑图片或摄像头验证黑标记检测、浮点/定点透视结果 |
| [rtl/](rtl/) | 把算法接到 FPGA；顶层为 `b_rectifier.v` |
| [examples/](examples/) | 查看演示图片、Python 阈值/ROI JSON、RTL 接线与参数配置示例 |
| [scripts/](scripts/) | 重建演示/测试向量，运行模型、RTL和脚本控制检查 |
| [sim/](sim/) | 阅读每项自检查 testbench；全部运行项由 `tests.list` 决定 |
| [vectors/](vectors/) | 查看可重建的输入像素、参考输出和逐请求数值向量 |
| [results/](results/) | 查阅本次验证报告、日志、RTL实际输出和结果图 |
| [docs/](docs/) | 阅读算法、逐信号接口、集成、硬件验证和修改记录 |
| [backups/](backups/) | 查看历史补充前快照及本次迁移前的旧结果/ModelSim库 |
| [docs/file_guide.md](docs/file_guide.md) | **逐文件作用、生成关系、该修改哪里，以及历史文件如何识别** |

推荐阅读顺序：本 README → [黑标记配置](docs/black_markers.md) → [逐文件指南](docs/file_guide.md) → [接口合同](docs/interfaces.md) → [集成配置](docs/integration_v1.md)。

## 原工程与完整备份

本次在独立副本 `member_b_perspective_black/` 中修改。用户指定的原工程 `/Users/yishuyu/Documents/FPGA/PythonProject_local/member_b_perspective_final/` 保持原样。

与本目录同级的 [member_b_perspective_original_2026-10-11.zip](../member_b_perspective_original_2026-10-11.zip) 是修改前的**完整工程备份**，包括源代码、文档、输入/结果文件、已有备份和隐藏文件。备份对应 245 个原文件、10,427,777 字节；[source_backup_manifest.json](../source_backup_manifest.json) 记录每个文件的相对路径、大小和 SHA256，并记录备份校验结果。恢复时把 ZIP 解压到新目录，检查清单后再使用，避免覆盖正在使用的工程。

本工程的 `backups/` 与这份完整 ZIP 用途不同：`2026-10-06_before_interface_v1_supplements/` 是原工程已有的局部历史备份；`2026-10-11_before_black_detection/` 保存迁移前的 `results/`、`work/` 和 `modelsim.ini`。这些日志和编译缓存属于旧四色版本，不能证明黑标记版本已通过。

## 快速运行与检查

在本工程根目录打开终端，使用 Python 3.10+ 安装依赖：

```text
python -m pip install -r requirements.txt
python -B scripts/run_checks.py
```

完整检查需要 `iverilog` 和 `vvp` 在 PATH 中。Windows 也可运行 `run_checks.bat`。运行器会重建向量，运行 Python 模型和可用的 Tcl 脚本控制检查，再执行 [sim/tests.list](sim/tests.list) 全部 RTL 项目，并重新核对 RTL 实际导出的 CSV 和 PNG。只有全部检查通过，才输出 `ALL_CHECKS_PASS`。缺少仿真器会报错；以下命令明确只检查软件：

```text
python -B scripts/run_checks.py --python-only
```

该模式输出 `PYTHON_ONLY_PASS RTL_NOT_RUN`，不能作为 RTL 验证结论。本次2026-10-11完整检查通过：17项Python模型、9项RTL自检查和11项Tcl脚本控制检查；静态CLI黑标记演示通过。真实结果与后续重跑状态以 [results/verification.json](results/verification.json) 的日期、测试列表和对应日志为准；详细验收规则在 [验证记录](docs/validation_record.md)。

已有 ModelSim/Questa 时，在包根目录执行：

```text
do run_modelsim.do
```

脚本逐文件编译，按同一清单运行全部 testbench，并严格读取二进制通过位。只有全套成功才输出 `ALL_MODELSIM_CHECKS_PASS`；原生日志写入 `results/modelsim_full.log`。`scripts/test_modelsim_script.py` 的 Tcl 命令替身检查只验证脚本控制行为。历史 ModelSim 五项编译及坐标单项记录位于备份中；本版原生全套、PDS、摄像头和开发板状态分别记录，不能互相替代。

## 运行黑标记图片演示

```text
python -B scripts/make_demo.py
```

它生成 640×480 输入场景与 210×297 矫正图。先查看 [examples/demo_preview.png](examples/demo_preview.png)。演示含黑色正文和图形，必须使用提供的局部 ROI 来只统计四个标记：

macOS/Linux：

```text
PYTHONPATH=python python -B -m brect.cli examples/demo_input.png --size 210 297 --thresholds examples/thresholds.json --rois examples/rois_demo.json --output results/my_photo
```

Windows CMD：

```text
set PYTHONPATH=python
python -B -m brect.cli examples/demo_input.png --size 210 297 --thresholds examples/thresholds.json --rois examples/rois_demo.json --output results/my_photo
```

输出目录包含 `float.png`、`fixed.png` 和 `parameters.json`。默认双线性；`--method nearest` 选择最近邻。换成自己的图片时，先按实际分辨率设置 `--rois`，再调 `--thresholds`。Python 接收 RGB；OpenCV 读图得到 BGR，传入 API 前应转换。

安装可选依赖 `opencv-python` 后，可使用摄像头参考入口：

```text
PYTHONPATH=python python -B -m brect.cli --camera 0 --size 210 297 --update-every 5 --thresholds examples/thresholds.json --rois examples/rois_demo.json
```

上面的 ROI 只适用于匹配演示位置和 640×480 有效区的画面；真实摄像头应另存对应的 ROI 文件。静态图片和摄像头共用同一阈值/ROI规则。OpenCV 用于采集、显示与色序转换，透视算法未调用 `cv2.warpPerspective`。逐像素 Python 是数值参考，不承诺电脑端实时帧率。

## 黑色判定与四角身份

默认黑色条件是每个通道同时满足闭区间 `0..64`：

```text
0 <= R <= 64 且 0 <= G <= 64 且 0 <= B <= 64
```

Python 阈值文件 [examples/thresholds.json](examples/thresholds.json) 使用唯一的 `black` 键：

```json
{"black": [[0, 0, 0], [64, 64, 64]]}
```

同一种黑色不能靠颜色区分角点，因此每个角点使用独立矩形 ROI。未传 ROI 时，图像按四象限分区；640×480 的默认值如下。奇数尺寸的右侧/下侧区域从 `W//2`、`H//2` 开始。

| 点/输出顺序 | Python 名称 | x 闭区间 | y 闭区间 |
| --- | --- | --- | --- |
| P0 / 左上 | `TL` | 0..319 | 0..239 |
| P1 / 右上 | `TR` | 320..639 | 0..239 |
| P2 / 右下 | `BR` | 320..639 | 240..479 |
| P3 / 左下 | `BL` | 0..319 | 240..479 |

四个 ROI 必须在源图内、各自非空且两两不重叠，端点均包含在内。阈值必须是 0..255 的整数范围，最小值不大于最大值。非法 Python 配置抛出 `ValueError`；非法 RTL 配置拒绝该帧，不产生有效四角。ROI 外的黑像素不参与四角统计。

ROI 内的所有黑像素都累加为该角点的质心，**没有连通域或“最大的黑块”筛选**。默认四象限适合干净背景的小场景；正文、黑边框、阴影或背景物体也落在 ROI 内时，会偏移质心，或因面积/跨度超限而拒绝。真实纸张演示应把 ROI 收窄到四个标记附近。详见 [黑标记配置与迁移](docs/black_markers.md)。

默认每个 ROI 至少 16、最多 4096 个命中像素，x/y 坐标跨度不超过128。四个质心按 TL/TR/BR/BL 顺序形成凸四边形；缺标记、散点、交叉或数值退化时不更新 H。标记中心应与真实纸角重合；印在纸内的标记会把外侧纸边裁掉，本版没有自动纸边偏移估计。

## Python API

```python
from brect import detect_markers, rectify_float, rectify_fixed

thresholds = {"black": [[0, 0, 0], [64, 64, 64]]}
rois = {
    "TL": [[198, 28], [222, 52]],
    "TR": [[473, 88], [497, 112]],
    "BR": [[498, 428], [522, 452]],
    "BL": [[78, 398], [102, 422]],
}
points, statistics = detect_markers(
    rgb_uint8, thresholds=thresholds,
    min_pixels=16, max_pixels=4096, max_span=128, rois=rois,
)
if points is not None:
    float_image, H = rectify_float(rgb_uint8, points, 210, 297)
    fixed_image, H_q = rectify_fixed(rgb_uint8, points, 210, 297)
```

`points` 顺序固定为 TL/TR/BR/BL；未成功检测返回 `None`，统计信息包含像素数、跨度、ROI和存在命中时的质心，可用于判断检测为什么被拒绝。可只把 `python/brect/` 导入已有工程。透视采样与原 v3 的逆映射和最后一次截断双线性规则一致；历史兼容结果及来源哈希保留在 [docs/provenance.json](docs/provenance.json)，本次兼容实跑结果只在指定 `--v3` 后确认。

## RTL 配置与 A/C 接入

把 [rtl/files.f](rtl/files.f) 列出的 9 个 `.v` 加入 A 的工程，顶层为 `b_rectifier`。端口名称、RGB位序、缓存合同和透视数值格式保持原接口。旧四色的24个阈值参数改为6个黑色阈值参数，并增加16个 ROI 端点参数：

| 参数 | 默认值/作用 |
| --- | --- |
| `SRC_W/SRC_H` | 640/480，完整源缓存尺寸 |
| `OUT_W/OUT_H` | 320/452，纸面矫正尺寸 |
| `UPDATE_EVERY` | 5，首次有效检测立即求 H，后续按成功检测节拍更新 |
| `MIN_PIXELS/MAX_PIXELS/MAX_SPAN` | 16/4096/128，逐 ROI 统计限制 |
| `BLACK_RMIN/RMAX`、`BLACK_GMIN/GMAX`、`BLACK_BMIN/BMAX` | 每通道0/64，统一黑阈值 |
| `P0..P3_XMIN/XMAX/YMIN/YMAX` | 按源尺寸定义默认四象限；P0/TL、P1/TR、P2/BR、P3/BL |

准确参数名和值见 [examples/integration_config.json](examples/integration_config.json)，覆写语法见 [docs/integration_v1.md](docs/integration_v1.md)。这些是编译/综合时参数。Python JSON不会配置 FPGA；改 RTL 阈值/ROI 后须重新编译、仿真和综合。旧的 `R_* / G_* / Y_* / B_*` 阈值覆写及 Python 四色字典不兼容，迁移步骤见 [docs/black_markers.md](docs/black_markers.md)。

可先编译完整端口透传示例：

```text
iverilog -g2005 -Wall -s b_rectifier_instance -o results/integration_example.vvp -f examples/integration_files.f
```

先用 `perspective_core` 的恒等 H 联调缓存，再接 `b_rectifier` 自动检测。所有 B 信号在同一个 `clk` 域；复位低有效，A/C负责跨域和同步释放。每个请求必须恰好响应一次，进入 B 的响应必须按请求顺序，填黑响应也占队列位置。A 在复位时清空外部在途事务，并为整张目的帧锁定同一完整源帧。完整信号表、延迟和边界规则在 [接口合同](docs/interfaces.md)。

## 数值格式与使用范围

| 数据 | 格式 | 规则 |
| --- | --- | --- |
| 四角和 x/y | 无符号12位整数 | 像素中心，范围0..4095；源/目的尺寸2..4096 |
| H 系数 | 有符号40位 Q16.24 | 参数求解使用signed64中间量，整数除法向零截断 |
| 像素路径乘加 | 有符号64位 | 正分母、非负分子及48位输入包络检查 |
| 源小数坐标 | 无符号20位 UQ12.8 | 正比值截断至1/256像素 |
| 插值权重 fx/fy | 无符号8位 | 补权重9位可表示256；RGB最终累加后右移16位 |
| 邻域地址 | 无符号24位 | 单位为像素，RGB888存储打包由A转换 |

H 小数24位、源坐标小数8位与原 v3 的 Q16.16 坐标不同。接回原插值参考时，坐标可左移8位；H接口不能直接套用旋转 sin/cos 的格式。四边形必须满足顺时针凸性、相邻边叉积至少16、`|g|,|k|<=4`，四输出角的量化分母均大于1/16。数学细节见 [算法说明](docs/algorithm.md)。

`req_error` 表示数值映射被拒绝；可表示的正坐标超出源图只清 `req_inside`。两类都按序返回一次有效黑像素。双线性采用严格边界，贴边量化可能产生黑行/黑列；规则和回归例子见 [接口合同](docs/interfaces.md)。

新 H 先进入 pending，只在 `dst_frame_start` 原子生效。失检或求解失败保留已提交的 H，`stale_frames` 表示陈旧程度。输出比例由实际纸面决定，例如A4纵向210:297；四角本身无法推断物理宽高比。

本包适用于平整纸面、固定或缓慢移动镜头和可控四标记位置。它不处理一般纸边识别、连通域分离、镜头畸变、曲面展开、OCR或手抖补偿。RTL每拍可接受一笔目的请求；实际帧率仍取决于目标器件时序和A的缓存供数。PDS资源、布局布线、Fmax、真实DDR/HDMI与开发板结果须实跑后填写 [验证记录](docs/validation_record.md)，50MHz示例约束不代表已测性能。
