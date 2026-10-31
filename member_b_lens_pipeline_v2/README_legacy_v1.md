# B 成员：四色标记实时透视矫正

交付范围：**红=纸张左上、绿=右上、黄=右下、蓝=左下 → 自动求四角 → FPGA 内低频计算逆透视 H → 每个输出像素求源坐标 → 最近邻/双线性插值**。不包含 A 的帧缓存、DDR3、接口拼接、跨时钟域，也不包含 C 的 HDMI、VTC、PLL 或其已有模块。

这是可以独立并入现有工程的算法包。原 v3 已在 `PythonProject_local/旋转算法参考/v3/` 找到，与项目缓存的 v3 文件 SHA256 一致，未修改。新模块延续 v3 的逆映射和最后一次截断的双线性规则，增加完整透视分母、自动标记和 RTL。验证还直接调用原 v3 插值函数做了 500 组兼容性对照。

## 先运行

在本目录打开终端，安装 Python 依赖（Python 3.10+）：

```text
python -m pip install -r requirements.txt
python -B scripts/run_checks.py
```

需要 Icarus Verilog 的 `iverilog`、`vvp` 在 PATH 中。Windows 可以运行 `run_checks.bat`。两套运行器共用 [sim/tests.list](sim/tests.list) 的八项测试清单；只有全部八项、Python 检查及实际 RTL 输出对比通过，才会打印 `ALL_CHECKS_PASS`。详细证据在 `results/verification.json` 和对应日志。缺仿真器时脚本会失败；`--python-only` 可以明确只验证软件，不能把该结果当成 RTL 已通过。

已有 ModelSim/Questa 时，先把工作目录切到包根目录，再运行：

```text
do run_modelsim.do
```

无需紫光库就能运行纯 RTL 测试。脚本在错误时停止，只有清单中八项全部通过才显示 `ALL_MODELSIM_CHECKS_PASS`，并保留 GUI。完整原生日志保存为 `results/modelsim_full.log`。当前没有八项全套 ModelSim 原生运行凭据；PDS/板卡也尚未运行。记录方法和待填字段见 [验证记录](docs/validation_record.md)。

下面两次 ModelSim 修正和五项 RTL 结果是 **2026-10-05 的历史证据**。它们证明当时的覆盖范围，不能代替本版八项全套结果。

2026-10-05 修正了用户在 ModelSim SE-64 2020.4 中报告的 `vlog-7` 启动错误：旧脚本将 `glob` 返回的多个路径作为一个文件名传给编译器，现在逐文件调用 `vlog`，RTL与testbench两处均已修正。`onbreak {resume}` 让仿真停止后继续检查 `test_passed`，失败仍中止脚本。更新后重新执行 `do run_modelsim.do` 即可，不需要改RTL。

本机用真实Tcl解释器和命令替身复现了原始错误，修复后通过四项脚本检查：文件参数逐个传入、编译失败即停止、测试未通过即停止、工程目录带空格。`scripts/run_checks.py` 在有 `tclsh` 时自动执行这些检查；它们检查脚本调用和控制流程，不能替代原生ModelSim仿真。

第二版脚本修正：用户后续ModelSim 2020.4日志确认全部九个RTL和五个testbench编译通过，坐标测试输出 `COORD_PASS 4329`，之后旧脚本却报通过标志错误。该标志只有1位；十进制显示有符号解释的风险，`examine` 还返回Tcl列表。新版改用 `-value -radix binary -noshowbase`，确认只返回一个值，再提取并严格比较 `"1"`。每项会打印 `test_passed(binary)=<1>`；0、X、Z、多值都拒绝。八项脚本回归覆盖这些情况。原生日志尚未确认后四个仿真顶层通过，不能据此称全套ModelSim已验证。

## Python 使用

```text
python -B scripts/make_demo.py
```

上面重新生成大尺寸演示图。先看 `examples/demo_preview.png`，再运行自己的图片：

macOS/Linux：

```text
PYTHONPATH=python python -B -m brect.cli examples/demo_input.png --size 210 297 --output results/my_photo
```

Windows CMD：

```text
set PYTHONPATH=python
python -B -m brect.cli examples/demo_input.png --size 210 297 --output results/my_photo
```

结果是 `float.png`、`fixed.png` 和四角/H 参数 JSON。`--method nearest` 选择最近邻，默认双线性。`--thresholds examples/thresholds.json` 载入自定义 RGB 阈值。软件图片使用 **RGB**；OpenCV 读图默认 BGR，传入前必须转换。

安装可选的 `opencv-python` 后，`--camera 0 --update-every 5` 提供摄像头采集/显示参考入口。OpenCV 仅用于采集、显示和色序转换；透视算法未使用 `cv2.warpPerspective`。逐像素 Python 是数值参考，**不承诺电脑实时帧率**。实时吞吐由 RTL 的每拍一个请求实现，最终帧率还取决于综合时序和 A 的缓存供数。

Python API：

```python
from brect import detect_markers, rectify_float, rectify_fixed
points, statistics = detect_markers(rgb_uint8)
if points is not None:
    float_image, H = rectify_float(rgb_uint8, points, 320, 452)
    fixed_image, H_q = rectify_fixed(rgb_uint8, points, 320, 452)
```

把 `python/brect/` 并入现有 v3 工程即可作为新透视功能导入；不用替换原旋转函数。

## 工程文件

| 位置 | 内容 |
| --- | --- |
| `python/brect/golden.py` | 阈值检测、独立 8×8 浮点 H 求解、手写逆映射和两种采样 |
| `python/brect/fixed.py` | 与 RTL 位精确一致的整数参数求解、坐标、地址、插值 |
| `rtl/marker_detector.v` | 参数化 RGB 阈值、计数/坐标累加、四颜色质心 |
| `rtl/homography_solver.v` | FPGA 内闭式四点求 H，8 次共享迭代除法 |
| `rtl/perspective_coord.v` | 三行乘加和双路流水除法，源坐标 UQ12.8 |
| `rtl/bilinear_interp.v` | RGB888 三段插值流水线 |
| `rtl/perspective_core.v` | 坐标、四邻域地址、缓存响应和插值边界 |
| `rtl/b_rectifier.v` | 自动参数更新、双缓冲 H、帧边界原子提交的 B wrapper |
| `rtl/*div*.v` | 可综合的厂商无关除法器，无逐像素组合 `/` |
| `sim/` | 八个自检查 testbench，统一清单为 `sim/tests.list` |
| `scripts/run_checks.py` | 重建向量、测试模型、编译 RTL、仿真、重查实际输出 |
| `vectors/` | 输入图片、坐标/参数/插值向量、逐像素参考、误差统计 |
| `results/` | 实跑日志、RTL 输出 CSV、RTL 重建 PNG 和验证报告 |
| `examples/b_rectifier_instance.v`、`examples/integration_files.f` | 可综合的具名端口透传示例与编译清单 |
| `examples/integration_config.json` | 默认参数、责任人和待确认配置记录；不会自动写入 RTL |
| `docs/` | 算法、逐信号接口、v1 接入配置、验证记录、板卡/PDS 操作、来源信息 |

新增测试覆盖按序可变缓存延迟、相邻请求切换插值、采集与目的请求并行、H 帧边界提交、处理中复位和实际默认尺寸的边缘行为。测试顶层、成功标志和验收条件见 [验证记录](docs/validation_record.md)；它们验证 B 接口，不能证明 DDR 带宽或整机帧率。

## 比赛演示的明确条件

1. 使用平整纸面和固定/缓慢移动的镜头。四色必须有足够饱和度，曝光稳定，背景及纸面正文尽量没有同色大面积图案。
2. **标记质心必须对应实际纸张四角。** 可以在支架上放标记，使中心与纸角重合。若把标记印在纸内部，按质心矫正会裁掉质心之外的纸边；本版没有自动纸边偏移估计。
3. 四角均在画面内，无遮挡。默认每种颜色 16..4096 个像素，包围盒坐标跨度 ≤128。缺失、过多、散落、非凸、交叉、分母过小和过度倾斜都拒绝更新。
4. 设置输出宽高体现真实纸面比例，例如 A4 纵向约为 210:297。仅有四角无法推断真实物理宽高比。
5. 默认每 5 次成功检测尝试更新一次 H，首次有效检测立即启动。新 H 只在 `dst_frame_start` 生效；后续失检保留最后一组有效 H，`stale_frames` 标明陈旧程度。外部可据此提示用户或选择冻结/原图显示。

阈值质心不是通用场景纸张识别：没有连通域分离、镜头畸变校正、曲面展开、OCR 或手抖补偿。极端斜视/不可见部分不能恢复。本包完成的是所选四色演示方案。

## 参数与数值

| 变量 | 位宽/小数位 | 规则 |
| --- | --- | --- |
| 四角与输入/输出 x,y | 无符号 12 位 / 0 | 像素中心；0..4095 |
| 源尺寸 | 参数，2..4096 | 输出尺寸也为 2..4096；建议先 640×480 输入、320×452 输出 |
| H 系数 | 有符号 40 位 / 24 | Q16.24；Q 的整数位包含符号 |
| 参数求解中间量 | 有符号 64 位 | 除法向零截断，禁止浮点硬件 |
| 像素路径乘加 | 有符号 64 位 / 24 | 除法前检查正分母、非负分子及 48 位范围 |
| 源坐标 | 无符号 20 位 / 8 | UQ12.8；正比值向下截断到 1/256 像素 |
| 插值 fx,fy | 无符号 8 位 | 补权重需要 9 位，能表示 256 |
| 行插值 / 最终累加 | 无符号 16 / 24 位 | 最后右移 16 位，不在行插值阶段提前舍入 |
| 邻域地址 | 无符号 24 位 | 单位为像素；RGB888 单独打包 |

v3 的 Q16.16 坐标不是本包的 UQ12.8。接回 v3 参考插值时可把源坐标左移 8 位；其余系数接口不能照抄 sin/cos 的 Q2.16。新 H 的 24 位小数用于减少 HD 尺寸下的透视分母量化误差。

所有阈值参数使用 0..255 的闭区间，MIN/MAX 合理设置且 `UPDATE_EVERY>=1`。`MAX_PIXELS<=16777216`、`MAX_SPAN<=4095`。颜色阈值、面积、跨度和更新频率都是 **RTL 编译/综合时参数**；`examples/thresholds.json` 只供 Python 使用，修改它不会改变 FPGA。真实摄像头阈值尚待 B 在实际曝光和灯光下调试，确认后须覆写 RTL 参数并重新综合。模块不支持任意更换数值格式。输入四角必须满足顺时针凸性及各相邻边叉积≥16；`|g|,|k|<=4`；四个输出角的量化分母均须 `>1/16`。完整数学见 [算法说明](docs/algorithm.md)。

`req_error` 表示数值映射被拒绝，`req_inside` 表示这笔请求能否读源图。负分子、分母过小、超出 48 位输入包络或比值≥4096 会置错误；可表示的正坐标超出源图，只清 `inside`。两类都填黑且必须按序返回一次响应。严格越界规则也适用于定点量化的贴边黑线；例子和回归决策见 [接口合同](docs/interfaces.md)。

## 集成与硬件验证

把 [rtl/files.f](rtl/files.f) 列出的九个 `.v` 加到 A 的工程，B 顶层为 `b_rectifier`。所有信号属于同一个 `clk` 域，复位低有效。先按照 [接口合同](docs/interfaces.md) 接缓存，**每个请求恰好响应一次，进入 B 的响应必须按请求顺序**。A 必须在复位时同时清空外部请求、响应和重排队列，防止旧响应进入已复位的 B。

接线和最终配置按 [v1 集成记录](docs/integration_v1.md) 执行。当前算法默认源图为 640×480、矫正纸面为 320×452；C 的默认扫描有效区为 1920×1080，三者各有用途。真实输入尺寸、显示窗口、缓存帧锁定和处理时钟由 A/C 确认。`docs/timing_example.sdc` 的 50 MHz 只是示例约束，实际处理时钟仍待定。

可先编译透传示例检查端口和参数：

```text
iverilog -g2005 -Wall -s b_rectifier_instance -o results/integration_example.vvp -f examples/integration_files.f
```

示例仅把具名端口接到 B，不包含 DDR、HDMI、CDC 或可直接下载的板级顶层。参数覆写和 ModelSim 编译方法见 [v1 集成记录](docs/integration_v1.md)。不要把算法内部缓存总线直接分配到板卡引脚。

本包已有电脑端 Python 和原五项 RTL 的历史功能证据，原 v3 文件保持不变；本版全套结果以当次生成的日志为准。**尚未做 PDS 综合/布局布线、资源占用/Fmax 检查或开发板验证。** 上板仍需 A/C 接入真实源帧缓存、四邻域供数、返回元数据、显示时序和实际时钟，再调颜色阈值与视频速率。板卡资源冲突、PDS 步骤和约束见 [板卡/PDS 说明](docs/board_pds.md)。本次 RTL 算法行为未改，补充项见 [变更记录](docs/changes_v1.md)。
