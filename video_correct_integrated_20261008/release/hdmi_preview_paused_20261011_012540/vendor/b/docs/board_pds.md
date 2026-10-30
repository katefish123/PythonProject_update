# 盘古676 / PDS 仿真与集成

## 已核对的板卡材料

来源：项目上传的《教程1_硬件实验指导手册_盘古676系列100Pro开发板.pdf》，共61页。封面及正文实际指向 **100Pro+ / MES2L676-100HP**，主控 **PG2L100H-6IFBG676**。不要与484封装100Pro或200Pro+约束混用。

| 项目 | 手册位置（印刷页 / PDF页） | 核查结果 |
| --- | --- | --- |
| FPGA、核心板、底板 | 10 / 14 | Logos2，核心板+扩展板 |
| DDR3 | 13、15 / 17、19 | 两颗512MB，合计8Gbit，32bit数据总线，最高1066Mbps/位；不是算法实测吞吐 |
| HDMI OUT | 13 / 17 | MS7210 |
| HDMI IN | 13 / 17 | MS7200 |
| 逻辑资源 | 16 / 20，已渲染核对表格 | 66,600 LUT6，133,200 FF，155块36Kbit DRM，表列5580Kbit总块RAM |
| 时钟 | 17..19 / 21..23 | 125MHz差分参考，N3/N2；27MHz单端系统参考，D18 |

**资源数量出入：** 手册PDF第20页写“APM(25×18乘法器)=740”。紫光同创[Logos2官方器件表](https://www.pangomicro.com/en/uploads/13964872_1729131653.pdf)列PG2L100H(X)=240 APM、PG2L200H=740。不能按740个给100H预算资源；以PDS选定的实际PG2L100H器件库及官方器件资料核实，本包没有声称已测出APM使用量。

640×480 RGB888单帧需要921,600字节，超过该器件约0.7MB块RAM总容量；全帧/双帧缓存一般交给DDR3。算法中不实例化DDR、PLL、HDMI PHY或专有IP，未编造板级管脚约束。

## PDS 中运行功能仿真

1. 建立独立的算法验证工程，选Logos2、PG2L100H、FBG676，对应实际-6I器件；不同PDS版本界面略有差异，以安装版本器件列表为准。
2. 把 `rtl/files.f` 的九个Verilog源加入Design Sources。列表中的路径相对本包根目录。RTL可按Verilog-2001编译。
3. 按 [sim/tests.list](../sim/tests.list) 把八个testbench加入Simulation Sources，测试文件按SystemVerilog编译，不加入综合。`sim/tests.list`是运行器共用清单，不是Verilog源文件；各顶层和成功标志见 [验证记录](validation_record.md)。
4. 在PDS仿真设置中选择已配置的ModelSim/Questa。让仿真工作目录为**包根目录**，便于读取 `vectors/` 和写 `results/`；保留本包 `results/` 目录。
5. 用仿真控制台`do run_modelsim.do`跑全部八项，保存`results/modelsim_full.log`。必须看到每项`test_passed(binary)=<1>`和最终`ALL_MODELSIM_CHECKS_PASS`。单项成功、只有编译通过或五项历史日志，都不能代替八项全套结果。
6. 需要波形时，Icarus运行 `vvp results/tb_b_rectifier.vvp +wave`；ModelSim可对 `dut` 加波形。此算法没有紫光原语，因此功能仿真不需要厂商库。

脚本包含ModelSim先前易遇到的检查标志可见性设置：`-voptargs=+acc`。每个tb只有完整通过后才置 `test_passed=1`。窗口不会在首项结束后退出。

如旧版报 `vlog-7`，并把多个 `.v` 路径放在同一对引号内，更新 `run_modelsim.do` 后重跑。修正版对RTL和SV文件均逐个调用编译器，避免把Tcl文件列表当成单个文件名。已有work库无需删除，脚本会重新编译。修正的Tcl参数边界和停止流程已用命令替身测试，ModelSim 2020.4完整仿真仍由本机实际运行确认。

2026-10-05的历史原生运行日志（[modelsim_user_coord.log](../results/modelsim_user_coord.log)）确认当时九个RTL和五个testbench编译零错误/警告，以及坐标测试`COORD_PASS 4329`。其后发生的成功标志误判由第二版脚本修正：明确二进制读取单值，避免1位逻辑1的有符号十进制解释，并提取`examine`返回的Tcl列表。规范依据：[ModelSim厂商命令参考](https://ww1.microchip.com/downloads/aemDocuments/documents/FPGA/swdocs/modelsim/modelsim_ref_2024_2.pdf)的examine与radix章节。原生日志没有打印旧读取值，因此具体旧值为-1是解释此现象的推断；新版会直接打印读取的二进制值以便确认。保留的[原生证据摘要](../results/modelsim_native_evidence.json)仍只说明历史范围，没有八项全套ModelSim通过结论。

## 在已有 A/C 工程里综合

1. 将九个RTL加入原PDS工程，在内部实例化 `b_rectifier`。保持A/C现有板级顶层、DDR例程、PLL、HDMI与真实管脚约束。
2. 先由A/C确认 [v1集成配置](integration_v1.md) 的最终值，再覆写实例化参数。默认640×480源、320×452目的只是起步参数；C的1920×1080有效扫描区另行配置。源有效区计数和RGB送入B，目的坐标由显示窗口/目的帧调度器提供。
3. 按 [接口合同](interfaces.md) 接缓存请求和带元数据的响应；每笔恰好响应一次，且必须在进入B前恢复请求顺序。先恒等H直通，再仿真向量H，最后四色自动更新。A锁定一张完整源帧供整张目的帧读取，并在复位时清空外部队列。不要把tb的四读口数组当作DDR实现。
4. `clk`必须绑定实际处理时钟，当前频率待A/C确认。仅做算法子模块综合时可以用`docs/timing_example.sdc`的50MHz示例；该值不是实测Fmax或最终处理时钟。完整工程使用实际PLL/官方例程的约束，27MHz晶振也不意味着算法clk固定27MHz。
5. 跑综合并检查是否出现锁存器、未连接信号、不正确有符号转换、乘法器/逻辑推断异常。记录LUT、FF、DRM、APM占用。
6. 跑布局布线/静态时序，检查实际目标时钟以及所有跨域路径。每拍能接受一笔是结构吞吐，不等于已达到74.25/148.5MHz。若高分辨率时序不足，先降低处理频率/输出尺寸，通过目的帧缓存解耦显示；进一步切分MAC/宽比较流水线时必须同步修改验证的延迟合同。
7. A/C使用官方PG2L100H-FBG676例程约束，核对板版本。手册N3/N2和D18只是核查用信息，不是B模块要自行新建的引脚文件。
8. 将工具版本、实际选定器件、顶层、参数、约束、目标时钟、LUT/FF/DRM/APM和时序结果填入 [验证记录](validation_record.md)，同时保存真实报告路径。尚未运行的项目保留`not_run`，未确定值保留`pending`；不能从示例约束填写Fmax。

不要把算法wrapper所有内部缓存总线直接当板级引脚。独立B工程主要用于功能仿真/综合检查，最终下载位流属于A/C完整顶层。

可选接线参考为 [b_rectifier_instance.v](../examples/b_rectifier_instance.v)。它只透传B算法端口，所有原参数均可覆写。PDS需要按 [integration_files.f](../examples/integration_files.f) 添加九个RTL和该示例；它不带DDR、HDMI、CDC或板级管脚。先做示例编译，确认连接后再放到A的真实顶层，具体命令见 [v1集成记录](integration_v1.md)。

## 上板需要调的项目

| 项目 | 当前状态 | 上板动作 |
| --- | --- | --- |
| 四色阈值/面积/跨度 | 合成图有历史功能证据；真实摄像头`not_run` | B记录原始RGB样本、曝光/灯光、误检/失检，再覆写编译时参数并重新综合 |
| 参数求解和换帧 | 原五项有历史功能证据；本版日志另记 | B/A确认帧脉冲、更新频率、坐标来源和纸角中心位置，检查采集/输出并行与H提交 |
| 四邻域供数 | 算法缓存模型可自检查；DDR`not_run` | A测DDR随机读取效率、缓存延迟/FIFO容量、按序重排、元数据对齐与源帧锁定 |
| 显示时序 | 不在B包内 | C/A对齐实际DE/HS/VS或使用目的帧缓存，确认RGB色序 |
| 资源/Fmax/下载 | PDS/开发板`not_run`；实际时钟`pending` | A/B跑实际器件综合和布局布线，记录资源、目标时钟、时序和板级IO约束 |
| 普通场景鲁棒性 | 限定为控制背景四色演示 | 排除同色杂物，避免遮挡、高光、过度斜视；验证纸页完整性 |

2026-10-05的本机验证使用Icarus及Python，当时未检测到PDS、ModelSim、Verilator或Yosys。该环境说明保留为历史记录。当前交付仍没有PDS资源、布局布线时序、Fmax或开发板实测凭据，所有硬件字段按 [验证记录](validation_record.md) 待运行后填写。
