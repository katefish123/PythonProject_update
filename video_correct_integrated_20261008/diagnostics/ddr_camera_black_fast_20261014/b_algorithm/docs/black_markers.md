# 黑色四角标记：配置和旧工程迁移

四个标记统一使用RGB黑色阈值，四角身份由4个独立矩形搜索区域（ROI）确定。输出点顺序固定为 `TL → TR → BR → BL`，对应RTL的 `P0 → P1 → P2 → P3`。透视输出仍是RGB888彩色；黑色只是角点检测条件。

## 检测过程

1. 对当前源图像素检查R、G、B是否同时落入统一闭区间，默认每个通道 `0..64`。
2. 命中黑色且位于某个ROI的像素，只计入这个角点的数量、x/y总和及包围盒。ROI外黑像素忽略。合法ROI不可能共享像素。
3. 每角要求 `MIN_PIXELS <= N <= MAX_PIXELS`，且 `xmax-xmin`、`ymax-ymin` 均不大于 `MAX_SPAN`。默认16/4096/128，跨度是坐标差而非含端点宽度。
4. 质心按 `(sum + floor(N/2)) // N` 求整数，恰好半像素向正方向取整。每角的x、y均按这个规则计算。
5. 四角有效后按TL/TR/BR/BL输出。Python同时检查顺时针凸四边形；RTL检测器输出统计有效四点，由后级solver检查四边形。不满足条件时不生成新的有效H。

RTL帧首/末有效像素仍被统计；帧末到来而上一次质心计算仍忙时，输出 `frame_dropped`（顶层`marker_dropped`），丢弃本帧快照。统计/配置失败时输出 `frame_reject`（顶层`marker_reject`）。快照丢弃和检测拒绝分开解释。失检后已提交H保持不变。

## Python阈值与ROI

`detect_markers(image, thresholds=None, min_pixels=16, max_pixels=4096, max_span=128, rois=None)` 接收 `uint8`、H×W×3的RGB数组，尺寸2..4096。阈值只允许唯一的`black`键：

```json
{"black": [[0, 0, 0], [64, 64, 64]]}
```

ROI必须恰好有TL/TR/BR/BL四个键，每个值为 `[[xmin,ymin],[xmax,ymax]]`，端点均包含：

```json
{
  "TL": [[198, 28], [222, 52]],
  "TR": [[473, 88], [497, 112]],
  "BR": [[498, 428], [522, 452]],
  "BL": [[78, 398], [102, 422]]
}
```

这是 [rois_demo.json](../examples/rois_demo.json) 的内容，对应640×480演示点 `(210,40)`、`(485,100)`、`(510,440)`、`(90,410)` 各自±12像素窗口。每个演示标记为9×9真黑方块，81个命中像素。真实输入必须用自己的分辨率和标记位置设置ROI。

未传ROI时默认四象限：左半 `[0,W//2-1]`、右半 `[W//2,W-1]`；上半 `[0,H//2-1]`、下半 `[H//2,H-1]`。奇数尺寸的中央列/行归右/下侧。省略阈值时使用0..64。

非法配置会抛出 `ValueError`，包括：阈值键错误、不是整数、维度错误、端点超出0..255、最小值大于最大值；ROI缺失/额外键、空窗口、越出源图或两ROI共享边界像素；统计参数不是整数或超出下列范围。图像中找不到足够有效角点时返回 `(None, statistics)`；它与配置错误不同。

```text
1 <= MIN_PIXELS <= MAX_PIXELS <= 16777216
0 <= MAX_SPAN <= 4095
```

`statistics` 按角点保存 `count`、`span`、`roi`，有命中像素时还保存 `centroid`。CLI静态图片和摄像头均通过 `--thresholds` 和 `--rois` 载入这些配置；`--update-every`控制摄像头参考的采样尝试节拍，RTL更新节拍使用其独立的 `UPDATE_EVERY` 参数。

## RTL参数

RTL `marker_detector`、`b_rectifier` 和 `examples/b_rectifier_instance.v` 都使用下列检测参数。RGB位序为 `[23:16]=R,[15:8]=G,[7:0]=B`。

| 参数 | 默认值 | 含义 |
| --- | --- | --- |
| `BLACK_RMIN` | 0 | 黑色R闭区间下界 |
| `BLACK_RMAX` | 64 | 黑色R闭区间上界 |
| `BLACK_GMIN` | 0 | 黑色G闭区间下界 |
| `BLACK_GMAX` | 64 | 黑色G闭区间上界 |
| `BLACK_BMIN` | 0 | 黑色B闭区间下界 |
| `BLACK_BMAX` | 64 | 黑色B闭区间上界 |
| `P0_XMIN/P0_XMAX/P0_YMIN/P0_YMAX` | 0 / SRC_W/2-1 / 0 / SRC_H/2-1 | 左上ROI |
| `P1_XMIN/P1_XMAX/P1_YMIN/P1_YMAX` | SRC_W/2 / SRC_W-1 / 0 / SRC_H/2-1 | 右上ROI |
| `P2_XMIN/P2_XMAX/P2_YMIN/P2_YMAX` | SRC_W/2 / SRC_W-1 / SRC_H/2 / SRC_H-1 | 右下ROI |
| `P3_XMIN/P3_XMAX/P3_YMIN/P3_YMAX` | 0 / SRC_W/2-1 / SRC_H/2 / SRC_H-1 | 左下ROI |

每角ROI需要 `0<=XMIN<=XMAX<SRC_W`、`0<=YMIN<=YMAX<SRC_H`；四ROI任意两者均不能重叠，含边界。6个阈值参数每通道需 `0<=MIN<=MAX<=255`。源尺寸和统计参数也必须合法。非法静态配置在空闲检测器处理帧末时拒绝整帧，不会因为没有黑像素而绕过配置检查；若帧末时忙则按既有快照丢弃规则处理。

`SRC_W/H`改变时，未覆写的ROI默认值随参数重新计算。若已经覆写局部ROI，需要同步修改它们；不得把640×480坐标原样复制到更小源图。

例如，演示场景的实例化检测参数可写为：

```verilog
.BLACK_RMIN(0), .BLACK_RMAX(64),
.BLACK_GMIN(0), .BLACK_GMAX(64),
.BLACK_BMIN(0), .BLACK_BMAX(64),
.P0_XMIN(198), .P0_XMAX(222), .P0_YMIN(28),  .P0_YMAX(52),
.P1_XMIN(473), .P1_XMAX(497), .P1_YMIN(88),  .P1_YMAX(112),
.P2_XMIN(498), .P2_XMAX(522), .P2_YMIN(428), .P2_YMAX(452),
.P3_XMIN(78),  .P3_XMAX(102), .P3_YMIN(398), .P3_YMAX(422)
```

这些是编译/综合时参数，不提供运行时ROI寄存器。JSON只给Python或记录最终配置；FPGA参数须写到A工程实例化、重新编译/仿真/综合。

## 从四色版本迁移

| 旧设置 | 新设置 |
| --- | --- |
| 红/绿/黄/蓝分别确定4角身份 | 4个黑标记，TL/TR/BR/BL身份由独立ROI确定 |
| Python `red/green/yellow/blue` 四色阈值字典 | 唯一 `black` 键，不兼容旧字典 |
| RTL `R_*`、`G_*`、`Y_*`、`B_*` 共24个阈值参数 | `BLACK_*` 共6个通道阈值，新增 `P0..P3_*` 共16个ROI端点参数 |
| 只调色阈值 | 同时调黑阈值、ROI、面积/跨度，并确认标记中心与纸角一致 |
| 旧结果日志/ModelSim优化库 | 从当前源码重建；旧文件已归档至`backups/2026-10-11_before_black_detection/` |

顶层输入输出端口、H格式、缓存元数据、顺序要求和RGB插值不变。A删除旧参数覆写，加入6个黑阈值与16个ROI值；B用真实画面检查4角计数/质心；然后按 [集成记录](integration_v1.md) 和 [验证记录](validation_record.md) 重新验证。

## 黑字与背景干扰

检测器累加ROI内**全部**黑像素，不挑最大连通块，不自动寻找纸边。纸面黑字、边框、背景黑物或阴影进入同一ROI，会共同影响质心；面积或跨度超限时拒绝。四象限只是起步范围，合成小场景亮背景可通过；有正文的大演示必须使用局部ROI。

调参时先收窄ROI，使每个窗口内只有对应标记且留足可移动余量，再用真实RGB样本调整阈值。收得太窄会在移动后失检；放得太大会引入正文/背景。光照变化、遮挡、黑标记越出窗口与镜头/纸面大幅移动，仍需按实际场景验证。
