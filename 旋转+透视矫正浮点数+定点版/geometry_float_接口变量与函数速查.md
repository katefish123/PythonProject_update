---
title: geometry_float.py 接口、变量与函数速查
date: 2026-10-04
input_shape: concept
subject: geometry_float.py 图像旋转与四点透视矫正
---

本文件总结 `geometry_float.py` 的主要接口、关键变量名称和函数作用，供阅读代码和对照 FPGA 计算时查阅。覆盖全部 24 个顶层函数，并选择与几何计算、采样、输出直接相关的变量和库接口；绘图样式变量、临时循环变量和异常变量未逐个列出。

源文件：[geometry_float.py](</Users/yishuyu/Documents/FPGA/PythonProject_local/v1_ab line/geometry_float.py>)。文中行号对应 2026-10-04 核对的源码，源码修改后行号可能变化。

程序支持图片旋转和四点透视矫正。核心数据流为：准备参数 → 为每个输出像素计算原图小数坐标 → 最近邻取整 → 检查边界 → 读取原图像素 → 保存图片、坐标表与参数。

**坐标约定决定所有接口的含义。** 左上像素中心为 `(0,0)`，x 向右、y 向下；正旋转角度表示屏幕上逆时针。几何坐标写作 `(x,y)`，图片数组访问写作 `image[y,x]`。参数中的逆矩阵始终用于“输出坐标 → 原图坐标”。

下面先列出命令行接口。默认路径以脚本所在目录 `BASE` 为基准。

| 子命令 | 功能 | 主要参数与默认行为 |
|---|---|---|
| `rotate` | 旋转输入图片 | 必须给出图片路径；`--angle` 指定角度，省略则提示输入；`--canvas` 为 `expand` 或 `same`，默认 `expand` |
| `rectify` | 四点透视矫正 | 必须给出图片路径；`--points` 提供四角，省略则鼠标选择；`--size W H` 指定输出宽高，省略则按边长估计 |
| `generate-tests` | 创建测试图片 | `--directory` 默认 `BASE/test_images`；`--font` 可指定中文字体 `.ttf/.ttc` |
| `demo` | 自测后运行全部演示 | 命令行入口先执行 `self_test()`，再生成测试图和 27 组演示结果 |
| `self-test` | 验证核心行为 | 使用内存中的小图片测试旋转、中心、采样、地址和透视，无需外部图片 |

`rotate` 和 `rectify` 共有的输出选项如下。

| 选项 | 含义 |
|---|---|
| `--output` | 输出图片路径，默认分别为 `BASE/output/float/rotate.png` 和 `BASE/output/float/rectify.png` |
| `--table` | 坐标 CSV 路径，默认放在输出图片旁，名称为 `<输出文件主名>_coordinates.csv` |
| `--points` 的格式 | `"x1,y1;x2,y2;x3,y3;x4,y4"`，顺序必须是左上、右上、右下、左下 |
| `--size W H` 的含义 | 两个整数，依次为输出宽、输出高；透视输出均须至少为 2 |

**主要 Python 接口可分为参数准备、坐标映射、采样和输出。** 表中签名保留原代码名称，返回值顺序与源码一致。

| 函数签名（起始行） | 输入要点 | 返回值 | 主要作用 |
|---|---|---|---|
| `rotation_parameters(width, height, angle, canvas="expand")`（27） | 原图宽高、角度（度）、画布模式 | 参数字典 `p` | 检查输入，计算正弦/余弦、输出尺寸和旋转逆矩阵；不读取像素 |
| `perspective_parameters(source_width, source_height, points, size=None)`（86） | 原图宽高、四角坐标、可选输出尺寸 | 参数字典 `p` | 验证角点，确定输出尺寸，求输出到原图的透视矩阵并检查分母 |
| `map_rotation(x, y, p)`（49） | 输出坐标，可为标量或可运算的 NumPy 数组 | `(sx, sy)` | 按旋转公式计算原图小数坐标 |
| `map_perspective(x, y, p)`（110） | 输出坐标、透视参数 | `(sx, sy)` | 按透视矩阵和随位置变化的分母计算原图小数坐标；无效分母对应 `NaN` |
| `map_grid(p)`（122） | 变换参数 | `(sx, sy)`，两个形状为 `(输出高, 输出宽)` 的数组 | 创建全部输出像素坐标，调用相应映射函数 |
| `sample_nearest(image, x_map, y_map)`（127） | 图片和同尺寸的二维原图坐标网格 | `(output, xi, yi, inside, addresses)` | 最近邻取整、检查边界、读取像素、生成像素地址；无效位置填零 |
| `render(image, p)`（146） | 图片及与其原图尺寸一致的参数 | `(output, sx, sy, xi, yi, inside, address)` | 将 `map_grid()` 与 `sample_nearest()` 串联，返回图片和完整中间结果 |
| `process(image, p, output_path, table_path=None, reference=True)`（379） | 图片、参数、输出路径、可选 CSV 路径及对照开关 | `metadata` 字典 | 渲染并保存图片、CSV、JSON；默认生成两种 OpenCV 对照图片和统计 |
| `opencv_reference(image, p)`（347） | 图片和变换参数 | `(unified, native, rx, ry)` | 用 OpenCV 独立计算几何参数，分别提供统一取整和原生变换结果 |

`map_rotation()` 和 `map_perspective()` 负责几何计算，`sample_nearest()` 负责像素读取。旋转渲染直接使用 `p["cos"]`、`p["sin"]` 等字段；透视渲染读取 `p["inverse_matrix"]`。

下面列出其余校验、文件、交互及测试函数。

| 函数签名（起始行） | 返回值 / 副作用 | 作用 |
|---|---|---|
| `_dimensions(width, height)`（20） | 合法时返回 `None`；否则抛出 `ValueError` | 检查宽高为整数且在 `1..16384` 内 |
| `_validate_corners(points, width, height)`（56） | `(4,2)` 的 `float64` 数组 `pts` | 检查角点有限、在原图内，并按规定方向形成严格凸四边形；不自动排序 |
| `_homography(src, dst)`（70） | `3×3` NumPy 矩阵 `h` | 根据四对对应点解 8 个线性方程，得到从 `src` 到 `dst` 的单应矩阵 |
| `read_image(path)`（154） | 图片数组 `data` | 读文件字节并用 OpenCV 按彩色解码；通道顺序为 BGR |
| `save_image(path, image)`（164） | 写图片文件；正常返回 `None` | 创建父目录，按扩展名编码并保存图片 |
| `dump_json(path, value)`（173） | 写 JSON 文件；正常返回 `None` | 保存带缩进的 UTF-8 JSON，保留中文，不允许 `NaN/Inf` |
| `export_table(path, x_map, y_map, xi, yi, in_bounds, address, extra=None)`（179） | 写 CSV 文件；正常返回 `None` | 每个输出像素一行，保存小数坐标、整数坐标、有效标志和地址；`extra` 可增加同形状列 |
| `parse_points(text)`（200） | 四个二维坐标组成的列表 | 解析分号分隔的角点字符串，检查形状 |
| `select_corners(image)`（210） | 四角坐标列表 | 显示预览，鼠标依次选四角，将预览坐标换回原图坐标，验证后返回 |
| `_cjk_font(size, explicit=None)`（260） | Pillow 字体对象 | 使用指定字体或查找可用中文字体；仅用于生成测试图 |
| `generate_test_images(directory, font=None)`（273） | `manifest` 字典；写入测试图和 `manifest.json` | 生成方向图、棋盘格、网格纸、边框图、小图及模拟透视图 |
| `_pixel_changes(a, b)`（375） | 不同像素数量，整数 | 比较两张图片；彩色像素任一通道不同就计一个变化像素 |
| `demo()`（403） | 写入演示图片、CSV、参数与汇总报告 | 运行 25 组旋转和 2 组透视演示，并检查 0°、90° 的关键行为 |
| `self_test()`（431） | 通过时打印结果；断言失败时抛出异常 | 检查直角旋转、奇偶中心、边界/半值、地址、透视分母、非法角点和尺寸不匹配 |
| `main()`（474） | 解析命令并执行相应流程 | 命令行入口；捕获部分输入、文件和 OpenCV 错误并报告 |

函数名前的单下划线是内部辅助函数的命名约定。`self_test()` 使用 `assert`，Python 的 `-O` 模式会禁用这些断言。

**参数字典 `p` 是准备阶段与计算阶段之间的接口。** 注意这里的 `width/height` 始终表示输出尺寸。

| 字段名 | 类型 / 取值 | 含义 |
|---|---|---|
| `kind` | `"rotation"` 或 `"perspective"` | 变换类型，决定使用哪种坐标映射 |
| `source_width`、`source_height` | 整数 | 原图宽高 |
| `width`、`height` | 整数 | 输出图宽高 |
| `inverse_matrix` | `3×3` 数值列表 | 输出坐标到原图坐标的齐次变换矩阵 |
| `angle` | 有限数；旋转专有 | 用户给出的角度，单位为度 |
| `cos`、`sin` | 浮点数；旋转专有 | 规范化角度的余弦和正弦 |
| `canvas` | `"expand"` 或 `"same"`；旋转专有 | 扩展画布或保留原图尺寸 |
| `points` | 四个二维坐标；透视专有 | 原图角点，依次为左上、右上、右下、左下 |
| `size_inferred` | 布尔值；透视专有 | `True` 表示没有显式提供 `size`，输出尺寸由边长估计 |

下面的变量表强调名称、所在阶段和具体含义。同名变量应结合所在函数判断。

| 变量名称 | 所在函数 / 阶段 | 含义与注意事项 |
|---|---|---|
| `BASE` | 全局 | 脚本所在目录，用于默认输入测试图和输出路径 |
| `image` | 渲染、采样、读写等 | 图片数组；通常彩色形状为 `(H,W,3)`，核心采样也支持二维灰度图 |
| `p` | 坐标映射、渲染、处理 | 变换参数字典 |
| `width`、`height` | `rotation_parameters()` | 传入的原图宽高 |
| `width`、`height` | `perspective_parameters()` | 推算或指定的输出宽高；原图尺寸由 `source_width/source_height` 表示 |
| `ow`、`oh` | `rotation_parameters()` | 输出宽高，即 output width / output height |
| `sw`、`sh` | `sample_nearest()` | 从图片形状取得的原图宽高，即 source width / source height |
| `w`、`h` | `demo()` | 读取图片的宽高；此处 `h` 是高度 |
| `angle` | 旋转参数、命令行 | 用户输入角度 |
| `theta` | `rotation_parameters()` | `angle % 360` 后的角度 |
| `cardinal` | `rotation_parameters()` | 0°、90°、180°、270° 的精确正弦/余弦查表 |
| `c`、`s` | `rotation_parameters()` | 分别为 `cos(theta)` 和 `sin(theta)` |
| `cx`、`cy` | 旋转参数、OpenCV 对照 | 原图中心，分别为 `(原图宽-1)/2` 和 `(原图高-1)/2` |
| `ox`、`oy` | `rotation_parameters()` | 输出图中心，分别为 `(输出宽-1)/2` 和 `(输出高-1)/2` |
| `dx`、`dy` | `map_rotation()` | 输出坐标减去输出中心后的相对坐标 |
| `points` | 透视准备、角点交互 | 原图中的四个角点 |
| `pts` | 角点检查、透视准备 | 转换成 `float64` 数组的角点 |
| `edges`、`following` | `_validate_corners()` | 四条边向量及它们各自的下一条边向量 |
| `crosses` | `_validate_corners()` | 相邻边叉积；用于检查凸性和点序方向 |
| `src`、`dst` | `_homography()` | 该次求解的起点和终点；函数求 `src → dst` |
| `dst` | `perspective_parameters()` | 输出矩形四角；通过 `_homography(dst, pts)` 求回原图的映射 |
| `a`、`b` | `_homography()` | 线性方程 `A·coefficients=b` 的系数矩阵行列表和右端值列表 |
| `coefficients` | `_homography()` | 解得的 8 个矩阵系数，追加 `1.0` 后组成 `3×3` 矩阵 |
| `inverse` | 参数准备函数 | 输出到原图的矩阵；旋转中为列表，透视中为 NumPy 数组 |
| `h` | 单应求解、透视映射、OpenCV 对照 | `3×3` 变换矩阵；不要与 `demo()` 中的图片高度 `h` 混淆 |
| `denominators` | `perspective_parameters()` | 输出四角的透视分母，全部须大于 `1e-12` |
| `d` | `map_perspective()`、OpenCV 对照 | 每个位置的透视分母：`h[2,0]*x + h[2,1]*y + h[2,2]` |
| `x`、`y` | 映射函数、`map_grid()` | 通常是输出横纵坐标或输出坐标网格；在 `_homography()` 中则是当前起点坐标 |
| `u`、`v` | `_homography()` | 当前对应点的终点坐标 |
| `x_map`、`y_map` | 采样、CSV 导出接口 | 原图小数坐标网格，与渲染中的 `sx/sy` 对应 |
| `sx`、`sy` | 映射、采样、渲染 | 对每个输出位置计算出的原图小数坐标 |
| `xi`、`yi` | 采样、渲染 | 由 `floor(sx+0.5)`、`floor(sy+0.5)` 得到的原图整数坐标，类型为 `int64` |
| `finite` | `sample_nearest()` | 两坐标有限且绝对值均小于 `2**62` 的布尔掩码，保护整数转换 |
| `inside` | 采样、渲染 | 两个取整坐标均位于原图内且通过 `finite` 检查的布尔掩码 |
| `in_bounds` | `export_table()` | `inside` 在导出接口中的参数名称 |
| `valid` | `map_perspective()` | 分母有限且绝对值大于 `1e-12` 的掩码 |
| `valid` | `process()` | 本实现与 OpenCV 的横纵小数坐标均有限的掩码，用于误差统计 |
| `output` | 采样、渲染、处理 | 输出图片，类型与输入图片一致，无效位置为零 |
| `addresses` / `address` | 采样 / 渲染及导出 | 按像素计的原图地址；有效位置为 `yi*sw+xi`，无效位置为 `-1` |
| `size` | 透视参数、OpenCV 对照 | `(宽,高)`；透视接口中可为 `None`，OpenCV 对照中是已确定的输出尺寸 |
| `forward` | 测试图生成、OpenCV 旋转对照 | 正向矩阵，方向取决于该调用：模拟图由矩形到四边形，旋转对照由原图到输出 |
| `rx`、`ry` | OpenCV 对照 | OpenCV 矩阵算出的原图小数坐标 |
| `ix`、`iy` | OpenCV 对照 | 对 `rx/ry` 统一取整后的坐标数组，使用 `float32` 交给 `cv2.remap()` |
| `safe` | OpenCV 对照 | 原图坐标有限且绝对值均小于 `32760` 的掩码；其余位置使用边界哨兵坐标 |
| `unified`、`native` | OpenCV 对照 | 统一取整后的对照图片 / OpenCV 原生变换图片 |
| `output_path`、`table_path` | `process()` | 结果图片路径 / 坐标表路径 |
| `metadata` | `process()` | 参数、坐标约定、采样约定和对照统计组成的字典 |
| `manifest` | 测试图生成、演示 | 测试图清单、透视角点、目标尺寸和测试角度等 |
| `reports` | `demo()` | 收集全部演示对照结果的列表 |
| `parser`、`sub`、`args` | `main()` | 总解析器、子命令管理器、解析后的命令行参数 |
| `scale`、`display_width`、`display_height` | `select_corners()` | 预览缩放比例和预览尺寸 |
| `preview`、`display`、`screen` | `select_corners()` | 基础预览图片、每轮绘制标记的图片、角点在预览中的位置 |

**主要库接口中，最需要记住的是 `np.linalg.norm()` 与 `np.linalg.solve()`：前者计算长度，后者求解矩阵系数。** 下表中的用途均对应当前文件中的实际调用。

| 库接口 / 常量 | 在本程序中的作用 |
|---|---|
| `np.linalg.norm(vector)` | 计算二维向量长度，即两角点间的欧氏距离，用于估计透视输出尺寸 |
| `np.linalg.solve(A, b)` | 求解 8 个线性方程，得到单应矩阵的 8 个系数 |
| `np.asarray(..., dtype=...)` | 将输入或矩阵转换为指定数值类型的数组 |
| `np.indices((H, W))` | 生成 y、x 坐标网格；返回顺序为 y 在前、x 在后 |
| `np.roll(..., -1, axis=0)` | 循环移位角点或边，构造相邻边及闭合四边形 |
| `np.isfinite(...)` | 检查有限值，排除 `NaN` 和无穷 |
| `np.floor(v + 0.5)` | 最近邻取整；半值取数值较大的整数 |
| `np.full(...)`、`np.zeros(...)` | 初始化整数坐标、无效地址和黑色输出图片 |
| `np.where(...)`、`np.errstate(...)` | 选择有效/无效透视坐标，并控制除零等警告 |
| `np.append(...)`、`reshape(3,3)` | 补上归一化系数 `1.0`，构造透视矩阵 |
| `np.any(...)`、`np.count_nonzero(...)` | 检查非法情况或统计不同像素数量 |
| `np.array_equal(...)`、`np.allclose(...)` | 在测试中比较像素是否完全相同、浮点坐标是否接近 |
| `math.radians()`、`math.cos()`、`math.sin()` | 角度转弧度，计算旋转系数 |
| `math.ceil()`、`math.floor()` | 扩展画布向上取整；自动尺寸按 `floor(L+0.5)` 取整 |
| `math.isfinite()` | 检查旋转角度是否合法 |
| `np.fromfile()`、`cv2.imdecode()` | 读取文件字节并解码图片 |
| `cv2.imencode()`、数组 `.tofile()` | 编码图片并写入文件 |
| `cv2.getRotationMatrix2D()` | 为旋转对照计算正向仿射矩阵 |
| `cv2.invertAffineTransform()` | 将旋转仿射矩阵转成逆映射矩阵 |
| `cv2.getPerspectiveTransform()` | 为透视对照计算四点变换矩阵 |
| `cv2.warpAffine()`、`cv2.warpPerspective()` | 执行原生几何变换；后者也用于生成模拟透视测试图 |
| `cv2.remap()` | 依据统一取整后的坐标读取原图，生成对照图片 |
| `cv2.INTER_NEAREST` | 最近邻采样模式 |
| `cv2.WARP_INVERSE_MAP` | 表明传入矩阵已经是输出到原图的映射 |
| `cv2.BORDER_CONSTANT` | 采用固定边界值；本程序设置为 0 |
| `cv2.resize()`、`cv2.INTER_AREA` | 生成选角点所用的缩放预览 |
| `cv2.namedWindow()`、`setMouseCallback()`、`imshow()`、`waitKey()` | 创建窗口，响应鼠标和键盘，显示预览 |
| `PIL.Image`、`ImageDraw`、`ImageFont` | 生成测试图片、线条和中文文字 |
| `argparse.ArgumentParser()` | 解析子命令和命令行选项 |
| `csv.writer()`、`json.dumps()` | 导出坐标 CSV 和参数 JSON |
| `Path.resolve()`、`.parent`、`.mkdir()`、`.write_text()` | 处理文件路径、创建目录和写文本 |

你之前询问的 `np.linalg.norm(pts[1]-pts[0])` 出现在 [原文件第 91 行](</Users/yishuyu/Documents/FPGA/PythonProject_local/v1_ab line/geometry_float.py:91>)。四个相关表达式对应四条边：

| 表达式 | 含义 |
|---|---|
| `np.linalg.norm(pts[1]-pts[0])` | 上边长度：右上到左上之间的距离 |
| `np.linalg.norm(pts[2]-pts[3])` | 下边长度：右下到左下之间的距离 |
| `np.linalg.norm(pts[3]-pts[0])` | 左边长度：左下到左上之间的距离 |
| `np.linalg.norm(pts[2]-pts[1])` | 右边长度：右下到右上之间的距离 |

二维向量 `(dx,dy)` 的长度为 `sqrt(dx*dx + dy*dy)`。自动输出宽度取上下边中较长者，高度取左右边中较长者，分别执行 `floor(长度+0.5)+1`。末尾加 1 是因为像素中心跨度与像素数量相差 1；自动尺寸不能保证恢复真实物体比例。

**计算时可直接对照以下四组公式。** `x,y` 为输出坐标，`sx,sy` 为原图小数坐标。

| 阶段 | 公式 / 规则 |
|---|---|
| 旋转逆映射 | `dx=x-ox`；`dy=y-oy`；`sx=c*dx-s*dy+cx`；`sy=s*dx+c*dy+cy` |
| 透视逆映射 | `d=h[2,0]*x+h[2,1]*y+h[2,2]`；`sx=(h[0,0]*x+h[0,1]*y+h[0,2])/d`；`sy=(h[1,0]*x+h[1,1]*y+h[1,2])/d` |
| 最近邻取整 | `xi=floor(sx+0.5)`；`yi=floor(sy+0.5)`；取整后检查原图边界 |
| 像素读取和地址 | 有效时 `output[y,x]=image[yi,xi]`，`address=yi*sw+xi`；无效时输出为 0、地址为 -1 |

例如：原图 `5×3`，旋转 `30°`，扩展输出为 `6×6`。输出坐标 `(3,2)` 对应原图小数坐标约 `(2.6830,0.8170)`，取整为 `(3,1)`，像素地址为 `1*5+3=8`。

以下是已将相关函数导入后的最小调用示例。`render()` 本身不写文件。

```python
import numpy as np

image = np.arange(15, dtype=np.uint8).reshape(3, 5)
p = rotation_parameters(5, 3, 30, canvas="expand")
output, sx, sy, xi, yi, inside, address = render(image, p)

image2 = np.zeros((21, 21), dtype=np.uint8)
points = [[0, 0], [10, 0], [10, 10], [0, 20]]
p2 = perspective_parameters(21, 21, points, size=(11, 11))
output2, sx2, sy2, xi2, yi2, inside2, address2 = render(image2, p2)
```

保存结果时调用 `process()`。假设输出文件是 `rotate.png`，默认产物如下：

| 文件 | 内容 |
|---|---|
| `rotate.png` | 本程序渲染结果 |
| `rotate_coordinates.csv` | 每个输出像素的坐标、有效标志和读取地址 |
| `rotate_parameters.json` | 变换参数、坐标和采样约定、OpenCV 对照统计 |
| `rotate_opencv_unified.png` | 统一使用 `floor(v+0.5)` 取整的 OpenCV 对照结果 |
| `rotate_opencv_native.png` | OpenCV 原生最近邻变换结果 |

设置 `reference=False` 时，只产生本程序的图片、CSV 和 JSON。坐标 CSV 按 y 后 x 排列，布尔值导出为 0/1，浮点数使用 17 位有效数字。

| CSV 字段 | 对应变量 / 含义 |
|---|---|
| `x_output`、`y_output` | 输出像素横纵坐标 |
| `x_source`、`y_source` | `sx/sy`，原图小数坐标 |
| `x_nearest`、`y_nearest` | `xi/yi`，原图整数坐标 |
| `in_bounds`、`out_of_bounds` | `inside` 及其取反，有效 / 无效 |
| `address_pixel` | `address`，按像素计的原图读取地址 |

| JSON 对照字段 | 含义 |
|---|---|
| `coordinate_max_abs_error` | 双方小数坐标均有限的位置中，横纵坐标差的最大绝对值 |
| `unified_nearest_pixel_changes` | 本结果与统一取整对照之间不同的像素数量 |
| `native_INTER_NEAREST_pixel_changes` | 本结果与 OpenCV 原生最近邻结果之间不同的像素数量 |

**对照代码时有几个容易混淆的细节。** 原图中心是 `((W-1)/2,(H-1)/2)`；`size` 的顺序是宽、高，而图片形状的顺序是高、宽。`_homography(src,dst)` 表示调用时的 `src→dst`，所以 `_homography(dst,pts)` 恰好得到输出矩形回到原图的映射。

越界检查发生在取整之后，因此 `sx=-0.5` 可以取整到 0。有限但越界的位置仍可能保留诸如 `xi=5` 的整数坐标，统一置为 `-1` 的是无效地址；无效地址不能直接用于读取，因为 NumPy 的 `-1` 索引会访问末尾元素。地址单位是像素，换成硬件字节地址还须结合像素格式和行跨度。

旋转与透视坐标通常使用双精度浮点数，输出像素保持输入类型。程序一次创建整张输出图的多个网格，是供核对坐标、取整、地址和像素关系的参考实现。FPGA 对照可按 `sx/sy → xi/yi → inside → address → output` 的顺序定位差异。
