# 给 A/C 的 B 模块接口合同

## 顶层 b_rectifier

所有输入均与 `clk` 同步。`rst_n` 低有效异步复位，解除复位应由集成工程同步。源视频时钟、DDR 时钟和显示时钟若不同，A 负责进入该域前后的 CDC/FIFO。

| 端口 | 方向/位宽 | 含义 |
| --- | --- | --- |
| `clk,rst_n` | 输入1位 | 算法处理时钟和低有效复位 |
| `src_valid` | 输入1位 | 这一拍有源 RGB 像素，只统计有效图像区 |
| `src_frame_start,src_frame_end` | 输入各1位 | 源帧开始/结束脉冲，可和首/末有效像素同拍，也可在前/后空拍 |
| `src_x,src_y` | 输入各12位 | 当前有效源像素坐标；不是带消隐的原始计数器 |
| `src_rgb` | 输入24位 | `[23:16]=R,[15:8]=G,[7:0]=B` |
| `dst_valid` | 输入1位 | 请求一个目的像素；连续为1可每拍接收一笔 |
| `dst_frame_start` | 输入1位 | 目的帧边界；提交待更新 H，可与第一目的像素同拍 |
| `dst_x,dst_y` | 输入各12位 | 本次目的坐标，在 `[0,OUT_W-1]×[0,OUT_H-1]`；由 A/C 生成 |
| `nearest` | 输入1位 | 1最近邻、0双线性，随每笔请求一起锁入标签 |
| `corners_valid` | 输出1位脉冲 | 完成一帧四颜色质心。四边形合法性由后级 solver 检查 |
| `x0,y0,x1,y1,x2,y2,x3,y3` | 输出各12位 | 红、绿、黄、蓝的整数质心，下一次有效检测前保持 |
| `marker_reject` | 输出1位脉冲 | 颜色数量/跨度/坐标/阈值多重命中等检查失败 |
| `marker_dropped` | 输出1位脉冲 | 上一次质心计算尚忙，当前帧末快照丢弃；当前帧像素统计仍进行 |
| `solver_reject` | 输出1位脉冲 | 四边形或定点 H 的有效包络检查失败 |
| `geometry_valid` | 输出1位 | 已提交过一套有效 H；首次成功前输出黑像素 |
| `params_pending` | 输出1位 | 有整套新 H 等目的帧边界提交 |
| `stale_frames` | 输出16位 | 上次 H 提交后经过的源帧数，饱和65535，提交清零 |
| `req_valid` | 输出1位 | 坐标阶段完成一笔请求，**包括需要填黑的位置** |
| `req_inside` | 输出1位 | 可读缓存。含有效 H、映射正确和采样边界检查 |
| `req_error` | 输出1位 | 数学/数值映射错误；普通图像外坐标只清inside |
| `req_tag` | 输出24位 | `{dst_y[11:0],dst_x[11:0]}` |
| `addr00,addr10,addr01,addr11` | 输出各24位 | 左上、右上、左下、右下的像素地址；无效时0，必须结合inside使用 |
| `req_fx,req_fy` | 输出各8位 | 双线性小数权重；最近邻/无效时0 |
| `rsp_valid` | 输入1位 | A 交回一笔缓存响应，包括填黑响应 |
| `rsp_inside` | 输入1位 | 必须与对应请求inside一致；无效请求交回0 |
| `rsp_tag` | 输入24位 | 原样返回req_tag |
| `rsp_fx,rsp_fy` | 输入各8位 | 原样返回同笔req_fx/fy |
| `p00,p10,p01,p11` | 输入各24位 | 同一笔请求四个邻域RGB；填黑响应可全0 |
| `out_valid` | 输出1位 | 该目的像素已完成，黑像素也输出有效位置 |
| `out_rgb,out_tag` | 输出各24位 | 矫正RGB和目的位置标签 |

参数 `SRC_W/H` 是缓存完整源图尺寸；`OUT_W/H` 是纸面矫正后的尺寸，不必与显示器的完整扫描模式相等。显示窗口放在哪里由 A/C 决定。标记参数、颜色阈值、UPDATE_EVERY 的定义见 README。

## 缓存交互的必要条件

1. 对每一个 `req_valid=1`，保存 `{req_inside,req_tag,req_fx,req_fy}`。`req_inside=1` 才读取四邻域；RGB888 打包为3字节还是32位存储字，由 A 决定并转换地址单位。
2. 请求无效时不读地址0，直接生成 `rsp_inside=0` 的黑色响应。仍然要返回一次 `rsp_valid=1`，否则输出会丢目的坐标，图像时序错位。
3. 四邻域同一帧、同一请求，和元数据同时返回。最近邻四地址相同，A 可只读一次并复制数据。
4. 顶层没有 ready/背压。A 可用调度器/FIFO控制 `dst_valid`，但已发出的请求必须被完整保存，缓存与B输出不能临时拒收。
5. 推荐按请求顺序返回。标签允许识别位置，但B不做乱序恢复；若乱序，A 应先重排，或写入目的帧缓存再显示。
6. 一张目的帧的所有源读必须锁定到同一个完整源帧，避免帧撕裂。角点来自最近观测源帧，本版不携带源帧ID；快速运动时低频 H 有滞后。A 的帧管理应处理对应关系，第一版演示采用固定镜头、缓慢移动纸张。
7. 单拍四读口存储模型只存在于 testbench。真实 DDR 随机访问不能按该仿真模型直接推断硬件；A需突发缓存、行缓存/银行划分或目的帧预计算等供数方式。

可变 DDR 延迟不能简单通过固定延迟 HDMI 同步信号解决。A 应选择有固定供数合同的缓存，或用目的帧缓冲/输出 FIFO 解耦 C 的固定扫描节奏。

## 延迟

`perspective_coord` 每拍都能接受一笔，E0采样输入，E22后出现req。缓存用L个寄存级，插值用3级。testbench缓存为1级：E23缓存响应、E24插值第一段、E25第二段、E26输出RGB。空拍跟随valid传播；复位清空整个流水线。

若 C 采用固定延迟的视频直通结构，需要按实际寄存级对齐HS/VS/DE，不只延迟有效区像素。若处理链有排队或目的帧缓存，使用 `out_tag` 放回目的位置，显示时由C的既有VTC从目的缓存取图。本包不实现这些A/C连接。

## 单独使用子模块

| 模块 | 输入 | 输出 | 说明 |
| --- | --- | --- | --- |
| `marker_detector` | clk/rst、pixel_valid、frame_start/end、pixel_x/y、RGB888 | corners_valid、frame_reject/dropped、busy、四点12位 | 可用参数单独修改24个RGB上下界；frame_end时忙会丢快照 |
| `homography_solver` | start、四点12位、固定源/目的尺寸参数 | busy、done/error、九个signed40 H | 只在busy=0接受start，done单拍；error时H保持 |
| `perspective_coord` | in_valid、12位dst坐标、九个signed40 H、任意TAG_W标签 | out_valid/error、20位UQ12.8源坐标、延迟标签 | 每请求采样系数；默认TAG_W=25，wrapper使用26位内部标签 |
| `bilinear_interp` | in_valid/inside、四个RGB888、8位fx/fy、TAG_W标签 | out_valid、RGB888、标签 | 3寄存级，inside=0仍输出valid黑像素 |
| `perspective_core` | 已算好的H、geometry_valid、目的坐标、nearest、缓存响应 | 缓存请求和最终像素 | 可绕过自动检测，调试固定H；其余缓存合同同顶层 |
| `unsigned_div_seq` | start、WIDTH位无符号分子/分母 | busy/done/error、商 | 默认64位；marker设40位，除0报错；busy期间start忽略 |
| `signed_div_seq` | start、signed64分子/分母 | busy/done/error、signed64商 | 向零截断，除0与INT64_MIN/-1拒绝 |
| `scaled_div_pipe` | 每拍非负WIDTH位分子/分母、valid、tag | UQ12.8商、valid/error、tag | 21级，比例≥4096拒绝；只作为坐标模块内部算子使用 |

## 最小固定H联调流程

先将 `perspective_core` 单独实例化，`geometry_valid=1`，使用整数恒等H：`h00=h11=h22=16777216`，其余0。目的坐标和源尺寸相同，最近邻与双线性都应逐像素直通。确认四邻域地址、有效与颜色后，再换 `vectors/manifest.json` 中的透视H，最后接入 `b_rectifier` 的自动检测和换帧。无需重写 C 的测试图或 VTC。
