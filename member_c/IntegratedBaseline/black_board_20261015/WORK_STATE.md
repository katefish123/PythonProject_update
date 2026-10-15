# 当前整合执行状态（2026-10-15）

## 本轮最终结果（优先于下方历史记录）

最终v3 `D:/FPGA/output/c_black_burst_merge_v3_20261015` 的33项统一新回归通过，PDS `build_20261015_103444` 构建及最终全部时序约束通过；RX setup+1.449ns、pixel+0.585ns、UI+1.097ns。sbit SHA256 `8b1b07ad67043c27cd4c47ec297afb8b5f92906fcce51dd7ee6e38afa84ec855`。`delivery/` 已生成并逐文件核验，hardware_accepted=false、board_replacement_allowed=false。

额外 `D:/FPGA/output/c_black_hold_display_20261015` 在实际RX短行/缺标/solver拒绝过程中检查旧图16896像素、恢复后新图768像素，全部匹配，旧bank未被提前替换。所有必要board来源冻结11文件；源归档后的复现重新生成13个C生产源码+9个B原始源码+14个hex完全相同，27个测试源码仅目录重定位差异。

最终三帧平均启动间隔508.319ms、最大publish图龄585.223ms，约1.97张不同结果/秒模型样本，仍未达到用户60张/秒；不要把修复可靠性称作实时完成。镜头float64+Q34.30整数模型17项通过，5000样本最大误差0.00753098925907源像素；真实标定、镜头RTL和硬件参数提交仍未完成。B9文件未改。

冻结main-C仍809c082且干净；开发没有烧录或操作OBS，板上540dd628基线未更换。后续工程优先级见NEXT_STEPS.md；需实际板测和独立代码审查，原审查agent额度失败不算审查通过。

## 10:25 更新（下方保留较早的执行设计）

已完成 filtered-clock 独立候选：`D:/FPGA/output/c_filtered_black_clock_20261015`，22项新回归通过；最终PDS `build_20261015_100532` 全部约束满足，RX setup WNS=+1.597ns（原−1.812ns），sys setup=+21.293ns。`clock_validation/` 和 `clock_sources/` 已保存绑定日志/时序/源码；该候选未合并板上burst/preview，明确不可替换板上程序。

已写入 `merge_board.py`：保留源预取/双bank/行读取和capture_guard，合并8拍完整采集载荷、两bank安全突发与缓存失效、原始预览/状态叠字、语义phase、writer状态稳定后的原因码、后台拒绝优先于完成清除。B原始9个RTL未修改。

中间合并v2：22项完整回归通过；另9项绑定测试通过，含真实RX短行→缺标→solver拒绝→恢复的整核测试、RX停钟与帧中复位。双bank writer/cache独立单测通过。全高清三帧每组1735680校正像素+同数显示像素精确；内检测组508.319ms平均启动间隔，仍约1.97张/s的三帧模型样本，非60fps；最大publish图龄585.223ms。

复核发现v2的engine地址/读协议原因编号与板上字库不一致，已改成原兼容定义1=地址、2=写协议、3=读协议，补入显式编号测试。最终候选 `D:/FPGA/output/c_black_burst_merge_v3_20261015` 将11项新测试纳入统一33项输入清单；正在重新compile+load及完整回归，**不能继承v2的通过结果**。最终合并版尚未完成PDS或板测。v1接口告警和extra v1/v2/v3的刺激问题日志保留，不算通过；修正后的extra v4全9项通过。

真实赛题与B最新分支审计已完成：A远端仍256b5ea，B仍4106f3b；包括B的最新黑标ZIP，确认没有镜头径向/切向、内参或真实标定及其加载。证据见 `../compliance_20261015/`。新增 `../lens_model_20261015/` 的独立float64 Brown参考、synthetic加载/不可变帧快照及11项单测（600独立展开多项式样本）已通过；定点/RTL、真实参数、硬件profile提交及原始角点去畸变尚未完成。用户60张不同完整校正图/秒目标保持。

独立代码审查agent因账户额度返回错误，未提供本轮审查结论；不记作审查通过。根代理已自行核对诊断字库与原因码，后续仍需完整审查。开发聊天未操作板/OBS，正式main-C和540dd628板上版本保持。

用户经“明确烧录专用需求”聊天补充授权：当前轮必须完成采集突发、状态预览、整核异常恢复及重新验证，不能仅列待办；开发聊天不烧录、不覆盖冻结包。

已推送 `c-pipeline-next / e3b0663`：A `256b5ea`、B `4106f3b`固定47文件快照，以及上一阶段21项通过/最终输入域时序失败的完整证据。`main-C / 809c082`干净且保持。上一阶段输出 `D:/FPGA/output/c_inline_black_geometry_v5_20261015`；布局布线 `build_20261015_092027` 最终RX WNS=-1.812ns，170 endpoints，其他域setup通过。未发布该sbit；包生成器正确拒绝失败时序。

上一阶段两个完整原生DDR模型各3帧，角点、H和像素均不同，1735680校正+同数显示像素精确；平均启动间隔691.647889→508.319370ms，减少26.506%，仍非实时视频。21项日志、输入清单、失败时序保存在 `../inline_geometry_20261014/validation`。不要更改这些已绑定输出或继承PASS给新源码。

## 正在做：时钟适配

保留B原始9个RTL的字节和数学公式。拟把原 `marker_detector` 运行于27MHz处理域，仅将可能贡献统计的黑色ROI像素，以及始末帧/异常终止事件从148.5MHz源域经小FIFO送入。丢弃的像素在原B检测器中hit=0，不改变计数、质心或边界；完整1920×1080仍写DDR，不做源图降采样。这个方案避免将B整个统计/40位除法控制放到RX域。

新 `capture_geometry` 将增加proc_clk/proc_rst_n，RX维护源坐标；FIFO载荷54位：pixel_valid、abort、first、last、token、bank、x12、y12、RGB24。SOF/EOF始终转发；短帧补abort EOF；FIFO溢出不能静默丢弃，终止事件需保持到成功写入。处理域以原B模块计算，绑定token/bank，结果独立toggle。必须测稀疏像素数学等价、首末像素、短帧、缺标、FIFO溢出及恢复。当前固定ROI每行最多两个102像素段，27MHz每两拍取FIFO时最坏积压仍需核验，不能无条件宣称任意ROI都无溢出。

## 然后：合并板上已验证修正

当前板上基线 `D:/FPGA/output/c_capture_burst_20261014`，release_burst sbit SHA256 `540dd628d92dbd477e6f8cbd4ccf7d0ebffbd1ae067929dc10015a7ae1a7793f`。其29项/时序/Program+Verify由烧录聊天执行；不继承资格。源生成脚本及预览/状态测试在 `C:/Users/Lenovo/Documents/ChatGPT/FPGA/initial_display_fix`。

1. 原子8拍capture writer：将板版单writer接入现有banked wrapper，透传BURST_BEATS、2048bit全载荷和failure_reason，基址按请求锁存。命令接受时engine一次锁存全载荷，最后WREADY才完成。
2. 保留v5带SOURCE_PREFETCH_ENABLE/SOURCE_BASE1的native engine，不能整体用板版旧engine替换。板版capture_command仅cmd_addr<SOURCE_WORDS；必须改为两个源区，检查完整64字范围与64字对齐，结果/BIST仍单拍。两个bank的写突发需失效相应64字源缓存。
3. 原生整机bench要改成按AWLEN和每个WREADY逐拍写RAM、比较每拍，支持AW/W同拍及随机停顿，不能继续AW时只写一个beat。
4. 合并rx_preview.v/status_overlay.v及display的preview/overlay/scan接口，保留A行读取和C capture_guard。低分辨率预览仅在尚无校正结果时取景，不作校正资格或清晰度结果。
5. core/session诊断：serial与overlap状态编号不同，统一语义phase；后台采集拒绝不能中止有效处理帧。优先报告真正fault/拒绝，避免complete_pulse同拍清除错误。join保留writer状态settle，几何失败显示3、solver4、watchdog5、tag错误11、RX12/13、packet14/15等。
6. 新增整核好→坏RX/缺标/solver失败→好，旧显示保持、拒绝计数、bank/token/新几何、后台坏采集与p_done同拍、复位/重连。协议测试覆盖两bank8拍、错误ID/last、超时、partial batch/错地址/旧token、缓存写后读、尾界。
7. 所有新输入先compile+load预检，再完整多帧/争用/故障回归、最终PDS；仅全部通过才形成新的可板测包。当前独立候选不覆盖任何现有目录。

## 随后实时流水线

用户最终目标仍为60张不同完整校正图/秒；烧录聊天拟定30张/秒、延迟≤100ms仅为待验证中间门槛，未获单独降档确认。现快照VS结束/下次才开始的协议最多约30个不同源帧/s，之后必须改连续交接。27MHz单lane单拍下界21.43ms也不能60。

完整B坐标轨迹分析已在 `../inline_geometry_20261014/trace_gather.py` /gather_trace.json，不是RTL或帧率。64×4空间块64条全相联FIFO（逻辑64KiB）三帧假设填充约3.49/3.46/3.42MB，四次8拍行突发约13644/13504/13376条；单纯64像素长条在第三图填充8.94MB而不稳定。后续先做UI域空间块gather及物理命令量，再选择单lane升频或双27MHz lane、解耦B坐标/插值/写回，带frame/bank/tag信用和排空规则。不能用HDMI 60Hz或三帧508ms成果宣称实时。

## 工具与协调

活跃工作树D:/FPGA/worktrees/c_pipeline_next；PDS D:/softwares/PDS/PDS_2022.2-SP6.4/bin/pds_shell.exe；ModelSim D:/softwares/modelsim/win64/vsim.exe。已有审查agent /root/ddr_writer_review 可只读复核（技能授权），不要并行改共享代码。不要杀其他聊天的vsim。开发不操作OBS/板；烧录聊天负责实际验收。每60秒内给简短有效进度。
