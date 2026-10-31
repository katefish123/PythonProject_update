# B 接入 v1：配置与责任记录

先由A/C确认下表的待定项，再把对应值覆写到B实例化参数。当前包默认源图640×480、纸面320×452；C默认1920×1080是显示有效扫描区。三组尺寸不能直接互换。B所有端口属于同一个处理时钟域，真实处理频率仍待定。

可编辑记录为 [integration_config.json](../examples/integration_config.json)。该JSON只记录配置，不会被RTL读取，也不会自动修改参数。修改JSON后，还必须修改A工程的参数覆写、约束和坐标调度，并重新验证。

## 默认、最终值与负责人

`default`表示随包起步值，`pending`表示未确认，`not_run`表示未执行验证。表中的责任人是A/B/C成员，不代表某个硬件项已经接好。

| 配置 | 包内默认/已知值 | 最终系统值与状态 | 负责人/下一步 |
| --- | --- | --- | --- |
| `SRC_W/H` | 640×480 | `pending` | A确认真实输入有效区和缓存尺寸，B复测 |
| `OUT_W/H` | 320×452 | `pending` | A/B确认纸面比例和目的缓存尺寸 |
| 算法`clk` | 无确定频率 | `pending` | A/C给出时钟来源、频率和约束；50MHz只在示例SDC中 |
| C显示有效区 | 1920×1080默认扫描 | 模式/刷新率`pending` | C确认PLL、像素时钟、完整时序及HDMI发送配置 |
| 显示窗口 | 无固定位置 | x/y/缩放/窗口外颜色`pending` | A/C确定纸面图在显示区内的位置 |
| `nearest` | 接入起步用0，双线性 | 默认接线选择`pending` | A/B确认；这是逐请求输入，不是RTL参数 |
| `UPDATE_EVERY` | 5 | 实际节拍`pending` | B根据运动和求解时间确认；首次成功检测立即尝试 |
| `MIN_PIXELS/MAX_PIXELS/MAX_SPAN` | 16/4096/128 | 真实标记统计`pending` | B用真实摄像头样本调整 |
| 四色通道阈值 | 下表RGB闭区间 | 真实曝光/灯光标定`pending` | B调整；A确认输入RGB色序 |
| 缓存像素打包 | 接口为RGB888、像素地址 | 字节/存储字/突发转换`pending` | A实现并验证四地址转换 |
| 响应顺序 | 每笔一次，必须按请求顺序 | 合同已定，实现`pending` | A在进入B前重排DDR结果，黑色响应也排队 |
| 缓存延迟/容量/吞吐 | 算法允许按序可变延迟，无背压 | 测量值`pending` | A测定并据容量控制`dst_valid` |
| 源帧锁定 | 一张目的帧锁定一张完整源帧 | 缓冲数量、选择/释放规则`pending` | A给出读写仲裁与帧管理方案 |
| H与采集帧关系 | B不输出源帧ID | 对应记录与滞后处理`pending` | A/B保留采集/检测/缓存版本信息 |
| 目的帧显示 | 完整输出后再供固定扫描 | 缓冲/FIFO/显示切换`pending` | A/C给出不会撕裂或断流的实现 |
| CDC与复位释放 | B内部同一`clk`域，`rst_n`低有效 | 跨域结构`pending` | A/C同步复位释放；A清空外部在途事务 |
| 板卡/PDS | 手册指向PG2L100H-6IFBG676 | 实际器件/版本/工程`pending`，验证`not_run` | A/B按 [板卡说明](board_pds.md) 核对 |

## 编译时颜色参数

| 角点/颜色 | R范围 | G范围 | B范围 | RTL参数前缀 |
| --- | --- | --- | --- | --- |
| 左上/红 | 160..255 | 0..110 | 0..110 | `R_RMIN/R_RMAX`、`R_GMIN/R_GMAX`、`R_BMIN/R_BMAX` |
| 右上/绿 | 0..110 | 140..255 | 0..110 | `G_RMIN/G_RMAX`、`G_GMIN/G_GMAX`、`G_BMIN/G_BMAX` |
| 右下/黄 | 160..255 | 140..255 | 0..110 | `Y_RMIN/Y_RMAX`、`Y_GMIN/Y_GMAX`、`Y_BMIN/Y_BMAX` |
| 左下/蓝 | 0..110 | 0..110 | 160..255 | `B_RMIN/B_RMAX`、`B_GMIN/B_GMAX`、`B_BMIN/B_BMAX` |

每个范围是包含端点的0..255整数区间。准确的32个参数名和值在JSON的`rtl_parameters`中；例如红色R通道参数是`R_RMIN`和`R_RMAX`。阈值、面积、跨度、尺寸和更新节拍均在编译/综合时生效。Python的 [thresholds.json](../examples/thresholds.json) 不会配置FPGA。

真实调参时，B保存未处理RGB图、曝光/白平衡/灯光、四色像素数和跨度，再检查背景同色物体、反光与遮挡。最终参数写回JSON及A工程的实例化覆写，重新综合，并在 [验证记录](validation_record.md) 填真实样本和日志。不能把合成图通过写成摄像头通过。

## 接线与参数覆写示例

[b_rectifier_instance.v](../examples/b_rectifier_instance.v)是可综合的具名端口透传示例，转发B全部参数和端口。A可复制其参数与具名连接到现有板级工程；例子本身不实现DDR、HDMI、CDC、视频窗口或管脚约束。

先在包根目录编译默认参数：

```text
iverilog -g2005 -Wall -s b_rectifier_instance -o results/integration_example.vvp -f examples/integration_files.f
```

下面的命令演示**真实的参数覆写语法**，只用于编译检查，不表示项目已选这些尺寸：

```text
iverilog -g2005 -Wall -s b_rectifier_instance -P b_rectifier_instance.SRC_W=1280 -P b_rectifier_instance.SRC_H=720 -P b_rectifier_instance.OUT_W=640 -P b_rectifier_instance.OUT_H=904 -P b_rectifier_instance.UPDATE_EVERY=3 -P b_rectifier_instance.R_RMIN=170 -o results/integration_override.vvp -f examples/integration_files.f
```

在A的PDS工程里，用实例的`#(.SRC_W(...), .SRC_H(...), .OUT_W(...), .OUT_H(...), ...)`覆写最终值；颜色参数同样写成`.R_RMIN(170)`等具名覆写。复制JSON不会完成这一步。每次更换尺寸，A还须同步改缓存行步长、目的坐标范围和C显示窗口，B复测首末行列和贴边规则。

ModelSim只编译示例时，可在包根目录执行：

```text
vlib work
vmap work work
vlog -work work -f examples/integration_files.f
```

已有`work`库时跳过`vlib work`。这一步检查端口/参数编译，示例没有自检查刺激，不能用其编译成功代替八项仿真。完整仿真仍运行`do run_modelsim.do`。

## A/C 必须完成的帧管理

1. A将真实视频有效区转换为从0开始的`src_x/y`，使RGB、有效位、源帧起止与源缓存写入一致。不同视频、DDR、显示时钟通过A的CDC结构进入/离开B域。
2. A为每张目的帧锁住已采集完整的源帧，直到该帧最后一笔缓存读取完成。每个请求的缓存帧版本由A保留，不能只根据响应到达时的“当前帧”取数。采集继续写其他缓冲，不能覆盖被锁源帧。
3. B仅在`dst_frame_start`提交已存在的pending H；同拍首像素使用新H。源采集与目的请求可并行，但H不在一张目的帧中途切换。H与锁定源帧的时间关系由A/B协调，当前演示允许低频更新带来的运动滞后。
4. A保存每笔`inside/tag/fx/fy`和四像素。所有请求各响应一次；有效、越界填黑、数值拒绝均按同一顺序进入B。缓存乱序完成时在B前重排。详见 [接口合同](interfaces.md)。
5. A按`out_tag`写入目的帧缓存。C仅扫描完整目的帧，显示帧边界再切换缓冲。若选固定延迟供数方案，A必须证明像素和HS/VS/DE的持续对齐；可变DDR延迟不能靠固定延迟同步信号解决。
6. 复位时A清空请求、响应、重排、输出队列，丢弃无法撤回的旧DDR读取结果。B复位不会清除A的队列，也不携带复位代次；复位后只响应新请求，新H建立前正确返回黑像素。

接入顺序：固定恒等H与缓存地址 → 向量透视H → 自动四色检测/换帧 → 实际尺寸 → PDS时序/资源 → 摄像头/DDR/HDMI整机。每步按 [验证记录](validation_record.md) 填实测结果；尚未运行的项继续保留`not_run`。
