# 图像几何实验：浮点参考 + FPGA 定点模拟

只有两个 Python 代码文件，两份都提供 A 旋转、B 手选四角透视矫正：

| 文件 | 用途 |
| --- | --- |
| `geometry_float.py` | 自己实现浮点坐标映射和最近邻采样，独立 OpenCV 对照，生成测试图 |
| `geometry_fixed.py` | 模拟整数乘加、舍入、透视除法与位宽检查，比较浮点/定点坐标、地址和像素 |

**请把两个文件放在同一个文件夹。** 定点版复用浮点文件的图片读写、选四角窗口、CPU 参数准备、CSV 导出及对照工具；定点的逐像素映射、取整和读像素独立使用整数运算。

## 安装与运行

依赖 Python 3.10+、NumPy、OpenCV 和 Pillow。本次已使用当前电脑的 Python 3.13 运行验证；没有改动旧工程或 `sources/` 材料。

在本文件所在文件夹打开终端：

```bash
python3 -m pip install -r requirements.txt
python3 geometry_float.py self-test
python3 geometry_fixed.py self-test
```

已有测试图和演示结果。重新生成与运行：

```bash
python3 geometry_float.py generate-tests
python3 geometry_float.py demo
python3 geometry_fixed.py demo
```

定点版逐像素做整数位宽检查，运行速度较慢，这是验证模型，未针对速度优化。CSV 大图每像素一行，体积较大。

## A 线路：输入角度 → 输出旋转图片

```bash
python3 geometry_float.py rotate test_images/directional.png --angle 30
python3 geometry_fixed.py rotate test_images/directional.png --angle 30 --frac-bits 16
```

省略 `--angle` 时在终端输入角度。`--output 路径.png` 指定输出；`--table 路径.csv` 指定坐标表。

统一约定：

- 左上像素中心为 `(0,0)`；`x` 向右，`y` 向下。
- 正角度在屏幕上为**逆时针**，负角度为顺时针。
- 默认 `--canvas expand`：扩展画布，包住旋转后的像素区域；越界填黑。
- **0°：宽高不变，输出与解码后的原图逐像素相等。** 这里比较像素，不比较 PNG/JPEG 文件的编码字节。
- **90°：输出宽高交换，不裁剪，与 `np.rot90(image)` 逐像素相等。** 例如原图 321×241，输出 241×321。
- `--canvas same` 保持原宽高，90°旋转非正方形图片会裁剪；这属于显式选择的另一种画布规则。

输入中心与输出中心：

```text
cx=(Win-1)/2, cy=(Hin-1)/2
ox=(Wout-1)/2, oy=(Hout-1)/2
Wout=ceil(Win*abs(cosθ)+Hin*abs(sinθ))    # expand
Hout=ceil(Win*abs(sinθ)+Hin*abs(cosθ))
dx=xout-ox, dy=yout-oy
xsrc=cosθ*dx-sinθ*dy+cx
ysrc=sinθ*dx+cosθ*dy+cy
```

0°/90°/180°/270°使用精确的 `0, ±1` 三角参数，避免浮点误差多出一行/列。浮点与定点共享 CPU 决定的输出尺寸及中心，不能在 FPGA 中另算一种尺寸后直接比较。

## B 线路：手选四角 → 输出透视矫正图片

```bash
python3 geometry_float.py rectify test_images/trapezoid_checkerboard.png --size 321 241
python3 geometry_fixed.py rectify test_images/trapezoid_checkerboard.png --size 321 241 --frac-bits 20
```

窗口中依次点选目标平面矩形的**左上 → 右上 → 右下 → 左下**；四个点分别对应输出的四角。左键选择、右键撤销、`R` 重选、`Enter` 确认、`Esc` 取消。点须构成凸四边形，不能交叉、重复或共线。逻辑四角顺序决定输出方向，选错顺序会改变方向。

大图片会缩小显示，鼠标坐标转换回原图像素中心。缩小显示的一个像素覆盖多个原图像素；要给出精确边界或复现一次点选，可直接手工填写坐标：

```bash
python3 geometry_float.py rectify test_images/trapezoid_checkerboard.png \
  --points "80,45;370,65;425,285;30,285" --size 321 241

python3 geometry_fixed.py rectify test_images/trapezoid_checkerboard.png \
  --points "80,45;370,65;425,285;30,285" --size 321 241 --frac-bits 20
```

本次验证中窗口成功启动，但自动化读取 Python 窗口超时，随后已关闭测试窗口；**真实鼠标点选、撤销、确认的完整流程尚未实测通过**。鼠标回调的缩放换算已做独立检查；直接给四角坐标的两份程序已实际运行并生成输出。

### 模型与适用范围

采用四点确定的**完整平面透视变换（单应矩阵）**，适用于相机斜拍的平面矩形，如纸张、棋盘、显示面板。它同时改变横纵坐标；不适用于曲面展开、明显镜头畸变或有深度起伏的物体。

CPU 根据原图四角与目标四角对应关系解 8 个线性方程，得到**输出→输入**矩阵 `H`，归一化令 `h22=1`：

```text
d=h20*xout+h21*yout+h22
xsrc=(h00*xout+h01*yout+h02)/d
ysrc=(h10*xout+h11*yout+h12)/d
```

位置相关的分母 `d` 是完整透视模型的关键；逐行寻找左右边界后拉伸不能替代这个模型。浮点版遇到接近零分母标为无效，定点版分母为零标为无效，均禁止读取缓存、输出黑色。

**四角只能确定到指定目标矩形的映射，不能独自确定原物体的真实宽高比。** 已知原始比例时用 `--size W H` 明确给出。省略时根据上下边、左右边的较长边长度估计输出大小，只得到方便观察的矩形。本测试原棋盘的角点跨度为 320×240，输出使用 321×241 个像素中心，内部方格每格 40×40。

合成斜拍图经过最近邻取样，矫正时再取样，已经丢失的细线和边界像素无法恢复。检查内部格子位置、形状、上下比例；不以外轮廓为矩形或与合成前图片逐像素相等作为唯一判断。

## 坐标、取样与地址分离

浮点版：`rotation_parameters`/`perspective_parameters` 准备参数；`map_rotation`/`map_perspective` 只算坐标，支持单个像素或数组；`map_grid` 生成全图坐标；`sample_nearest` 负责取整、边界和读像素。

定点版：`quantize_parameters` 量化 CPU 参数；`map_rotation`/`map_perspective` 返回整数 Q 坐标和有效标志；`sample_fixed` 单独取整、检查边界、生成地址和读取像素。

最近邻明确为：

```text
ix=floor(xsrc+0.5)
iy=floor(ysrc+0.5)
# 所有恰好半值向正无穷：0.5→1, -0.5→0, -1.5→-1
inside=(映射有效 且 0<=ix<Win 且 0<=iy<Hin)
addr=iy*Win+ix        # inside 为真才允许读
addr=-1              # 越界或无效的哨兵，禁止当实际地址使用
```

以取整后的整数坐标判断边界；例如 `xsrc=-0.5` 取整为 0，允许读取边缘像素。不能先把所有负的小数坐标直接判为越界。

每个运行默认导出 CSV，列包括：

| 列 | 含义 |
| --- | --- |
| `x_output,y_output` | 输出像素中心整数坐标；每行一个像素，先 y 后 x |
| `x_source,y_source` | 对应原图小数坐标；定点表显示整数 Q 坐标除以比例 |
| `x_nearest,y_nearest` | 实际最近邻整数坐标 |
| `in_bounds,out_of_bounds` | 是否允许读取原图，及其反向标志 |
| `address_pixel` | 行优先像素地址；无效或越界为 -1 |
| `x_source_q,y_source_q` | 定点原始整数坐标，供 Verilog 逐项比较 |
| `denominator_raw` | 定点除法的原始整数分母；旋转为未缩放整数 2，透视为带 F 位小数的累加值 |
| `fixed_mapping_valid` | 定点映射是否有效；透视分母零时为 0 |

图片使用 OpenCV 的 BGR 三通道 8 位格式；`address_pixel` **以一个像素为单位**。若缓存按 B/G/R 字节连续存储，字节地址为 `3*address_pixel+channel`；若像素打包为更宽数据，应按实际总线布局换算。

先查看 `output/float/tiny_8x6_rotate_30_coordinates.csv` 与 `output/fixed/tiny_rotation_30_comparison.csv`。原图为 8×6，30°扩展输出为 10×10，CSV 有 100 个像素记录，适合逐个手算。

## 定点格式与硬件对齐

默认 `F=16`，`S=2^F`，保存 `q≈value*S`。可用 `--frac-bits 10..20`，每次运行的 JSON 保存全部整数参数和运算规则。

| 变量 | 位宽 | 有符号 | 小数位 |
| --- | --- | --- | --- |
| 输出 x/y、宽高、旋转倍增中心偏移 dx2/dy2 | 32 | 是 | 0 |
| sin/cos、透视矩阵系数 | 32 | 是 | F |
| 原图坐标 xq/yq | 32 | 是 | F |
| 系数×整数坐标、旋转乘加、透视行累加 | 64 | 是 | F |
| 透视分子再乘 S | 64 | 是 | 2F |
| 最近邻整数 ix/iy | 32 | 是 | 0 |
| 像素地址、中间地址乘加 | 64 | 是 | 0 |
| 有效、越界标志 | 1 | 否 | 0 |

`signed32/F16` 的可表示坐标范围为 `[-32768,32768)`；`signed32/F20` 为 `[-2048,2048)`。更高小数精度会缩小范围，也限制透视平移系数的范围；超出时程序报错，不静默截断。浮点 CLI 的尺寸上限为 16384，定点仍必须满足对应 Q 格式范围。

### 旋转

CPU 先算、量化 sin/cos；FPGA 像素路径只需乘加：

```text
cq=floor(cosθ*S+0.5); sq=floor(sinθ*S+0.5)
dx2=2*xout-(Wout-1); dy2=2*yout-(Hout-1)
xq=round_half_up((cq*dx2-sq*dy2+(Win-1)*S)/2)
yq=round_half_up((sq*dx2+cq*dy2+(Hin-1)*S)/2)
```

倍增坐标精确保留整数或半整数中心，避免奇偶宽高导致半像素丢失。除 2 相当于移一位，但须遵循半值向正无穷的舍入，不能仅用算术右移截断。

### 透视

```text
hij_q=floor(hij*S+0.5)
nx=h00_q*xout+h01_q*yout+h02_q
ny=h10_q*xout+h11_q*yout+h12_q
d =h20_q*xout+h21_q*yout+h22_q
xq=round_half_up(nx*S/d)
yq=round_half_up(ny*S/d)
ix=(xq+S//2)//S; iy=(yq+S//2)//S
```

系数乘整数像素坐标后仍有 F 位小数；透视分子乘 S 后有 2F 位小数，除以带 F 位小数的分母恢复为 F 位。中间保留完整乘积，指定位置才舍入。原图坐标先舍入到 Q 格式，再做最近邻整数取样；这两个步骤不能随意合并。

除法实现使用有符号整数商与余数决定最近舍入，负数也半值向正无穷。Python `//` 向负无穷取整，Verilog `/` 的有符号商通常向零截断；直接照搬除法符号不足以保证一致，必须实现这里的舍入规则。

所有声明为 32/64 位的乘积、累加、除法与缩窄都会做范围检查；超出即 `FixedOverflowError`，终止运行。它模拟的是**不允许溢出的契约**，没有采用回绕或饱和。FPGA 对齐时使用相同参数、位宽和规则；若硬件选择回绕/饱和，需要先修改模型定义，不能混着比较。

### 已观察到的精度差异

下列结果来自本文件夹测试图，在当前环境中实际运行，坐标误差为 `max(|dx|,|dy|)` 的全图最大值：

| 测试 | 小数位 F | 最大坐标误差/像素 | 地址变化 | 输出像素变化 |
| --- | --- | --- | --- | --- |
| 方向图 0°/90°/180° | 16 | 0 | 0 | 0 |
| 方向图 30°/−30° | 16 | 0.000483221 | 0 | 0 |
| 8×6 小图 30° | 16 | 0.0000109271 | 0 | 0 |
| 棋盘四点透视 321×241 | 16 | 1.056655884 | 32226 | 1145 |
| 同一棋盘四点透视 | 20 | 0.026966095 | 862 | 15 |

透视分母系数很小，对量化尤其敏感。本测试推荐先用 F20 检查透视效果，再根据图像大小、误差需求设计硬件位宽。F20 仍存在地址/像素变化；不能声称与浮点逐像素相同。棋盘有重复颜色，取样地址改变也可能读到相同颜色，所以地址变化与像素变化都要看。

## OpenCV 对照与验证

浮点核心自己解矩阵、自己算坐标和读取像素。独立对照用 OpenCV 的旋转矩阵与四点透视矩阵重新计算几何参数，并比较坐标；没有把核心输出作为几何真值。

两个对照结果分别保存：

1. `*_opencv_unified.png`：OpenCV 独立坐标先按 `floor(v+0.5)` 取整，再用整数坐标 `cv2.remap(..., INTER_NEAREST)`，统一最近邻规则。
2. `*_opencv_native.png`：直接 `warpAffine` 或 `warpPerspective`，明确 `INTER_NEAREST | WARP_INVERSE_MAP`、输出尺寸及黑色边界。记录原生取整/内部精度带来的差异。

在当前电脑的 OpenCV 5.0.0 中，浮点 27 个演示两种对照均为 0 像素差异，独立坐标最大差异低于 `2e-13` 像素。这个结果不代表所有参数、平台或 OpenCV 版本都完全一致；恰好半像素或原生内部量化可能改变取样。本程序的明确规则才是浮点/定点/RTL 对齐契约。OpenCV 对逆映射及该标志的定义见 [官方几何变换文档](https://docs.opencv.org/4.x/da/d54/group__imgproc__transform.html)。位宽、量化与溢出是定点定义的一部分，可参考 [AMD UG1399](https://docs.amd.com/r/2023.1-English/ug1399-vitis-hls/Overview-of-Arbitrary-Precision-Fixed-Point-Data-Types)。

自测包括非正方形、奇偶尺寸、0°/90°/180°/270°、负角度、半像素正负取整、黑边与非法地址、完整透视分母、单位透视、退化角点及溢出。另有手算非仿射矩阵检查内部点与地址，避免只观察外轮廓。

**本次没有生成或运行 Verilog。** 后续将相同 JSON 整数参数交给 RTL，逐项比较 `x_source_q/y_source_q → x_nearest/y_nearest → 越界/有效 → address_pixel → BGR 像素`，才能确认定点版与 Verilog 一致。

## 文件夹内容

- `test_images/`：7 张测试图及 `manifest.json`（已知角点、输出大小、角度）。
- `output/float/`：五类图像 × 五个角度，以及两张透视矫正结果；图片、CSV、参数、OpenCV 对照和验证报告。
- `output/fixed/`：定点输出、浮点参考、像素差异图、参数及比较报告；8×6 小图的完整坐标表和逐项比较表。
- `preview.png`：方向与透视结果概览。
- `README.md`、`requirements.txt`：使用说明和依赖。

便携包 `image_geometry_lab.zip` 包含两份代码、测试图、效果图、参数/报告和小图 CSV。为控制体积，其他大图 CSV 保留在项目文件夹，未收入压缩包；运行对应 CLI 或浮点 `demo` 可重新导出。

中文测试图显式加载系统中文字体。macOS 可用黑体/PingFang，Windows 可用微软雅黑，Linux 可用 Noto CJK；若没有字体，用 `generate-tests --font /路径/中文字体.ttc` 指定。未找到中文字体会报错，避免生成方块字测试图。
