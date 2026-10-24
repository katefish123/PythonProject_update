# c1291362 实板停更证据分析

输入记录：`C:/Users/Lenovo/Documents/ChatGPT/FPGA/initial_display_fix/integrated_hud_20261024_082612/report.json`。本分析只读取记录与合格包源码，不访问硬件。

3.1172391秒内物理帧+188，接纳/丢弃/拒收各+94；校正发布及PIX帧号均保持1，PIX RAW为0，结果地址0x200000。确实零新图，不能解释成单纯HELD阈值。LED5由用户确认亮，代表显示欠载历史锁存。

## 已核对的逻辑

- RX结束原因为13表示overflow，为12表示非完整帧。二者由END记录传递并正常拒收，不一定置位永久source fault。所以current_mask=0不能排除这些失败。
- 当前FIFO峰值1024达到深度；它是历史峰，不能单独证明本区间94次拒收均由overflow引起。缺少拒收原因直方图读出。
- row0d firstmask8表示ALIGN历史，不代表当前ALIGN仍坏。
- row16值为1<<64。按top拼接，first_fifo_valid=1，first_fifo_peak=0，source_first_valid=0。捕获条件diagnostic_reason==7包含memory_fault，不只FIFOoverflow，故此记录不能单独归因。修改其含义前应保留原始码流与数据。
- writer每收满8个256位包才发一个8拍突发，等待写ACK期间不继续组下一块；上游依赖1024深度异步FIFO吸收等待。显示client2优先于capture0和processor1，0/1相互公平。此结构在不利服务分布下存在吞吐压力，但尚未证明是这次停更唯一根因。
- display行不匹配时置underrun，缺行输出0。当前亮LED5为这一路已失败的证据；不说明源DDR内容一定正常或异常。

## 接下来需要的最少区分证据

1. RAW请求后确认实际PIX RAW=1的源图和相隔数秒的计数，再恢复实际PIX RAW=0。若RAW也不更新，不能仅修B算法或结果显示。
2. 当前没有上屏的reject_reason_counts[12/13/14/15]，是区分RX尺寸错误、RX溢出、writer协议/不完整写的关键。若现有证据仍不足，应准备仅增加诊断字段的新候选，暴露这些计数及服务次数/累计等待；改任何生产RTL均须重新完整时序资格，不能用本次旧仿真冒充新候选通过。
3. max_first_w=322/max_first_r=332只代表最大值，缺乏发生次数和平均值，不能假定每个事务都如此，也不能由最大值推导实际带宽。

四窗全范围engine测试验证协议、掩码、字地址/拍/通道和响应数据；它没有模拟真实PHY服务分布与三个客户的实时竞争，不能据其通过否定本次实板失败。当前未修改生产RTL或重新烧录；根因未定，优先候选为采集/显示共享服务供给不足或RX帧完整性问题。

## 08:28 单键对照追加

`initial_display_fix/integrated_raw_20261024_082825/source_1.png` 上部出现真实布景和相机HDMI提示文字，约331行以下大片近常量暗灰；HUD未显示，decoder为空，实际RAW模式不能确认。由此排除“完全没有任何真实输入数据到输出”的笼统说法，不证明源帧完整。

顶层presentation控制中，单KEY1不清diagnostic_requested；仅双键同时保持至阈值翻转，或cfg_rst复位清零。RAW模式不隐藏HUD。显示模块末尾的overlay覆盖也不受line_ok限制，因此不能把HUD消失直接归因于缺行。真实按键电平、复位和时点未知，不能指责用户按错。后续先保留释放图，再由烧录窗口恢复诊断层核对实际PIX模式。

## 08:29 释放图与模式切换前提

释放图实景延伸至约665行，仍未显示HUD。不能认定模式已切换：`c_frame_mode_controller`只在WAIT_SOURCE且完整frame_valid被接纳时读取raw_request并发布新模式，KEY1不是立即切换显示地址的MUX。持续拒帧时，按下/释放均可不改变PIX模式。

显示器在每次扫描publication_boundary清line_valid、增加display_gen并将prefetch_row归零；旧代ACK不能推进新cursor。因此设计并不按几十秒持续积累同一帧的可见行数；331→665的两张图变化不能单独证明后台逐行缓慢填充。下一证据应为自然等待图及一次恢复HUD后的实际模式、银行、帧号和发布计数。若仍停更，诊断候选必须暴露拒帧原因而非继续依赖模式按键。

## 独立静态吞吐审计追加（c129精确包，2026-10-24）

范围：`D:/FPGA/deliveries/FullHD_Lens_IntegratedRepair_20261023/sources`，只读；未运行仿真、PDS或硬件。下列结论是静态必要条件及可反证假设，不是实板根因判定。

### 最强可验证压力链

第一幅图发布后，显示器开始每个HDMI扫描都重读整幅DDR；即使PIX帧号不变，也没有整帧本地缓存。`ddr_result_display_raw_corrected.v:271-288`每扫描重置行代际/游标，`:163-180`每64像素读回后串行写8次256位行RAM，再申请下一块；完整1920行需要30块。四个物理行和最多三行前瞻吸收有限抖动，不提供无限累计带宽。

更正上文客户编号：`video_correct_ddr_continuous_core.v:168-173`外层c0是背景处理br，c1是capture，c2是display。只有br在display_prefetch_busy时禁止；capture一直可以申请。`ddr_arbiter3_turnaround.v:25-35`display具有请求优先级，已接受事务不可抢占，响应仍给旧owner。不能把当前逻辑解释成显示预取期间禁止采集。

`continuous_capture_writer.v:22-25,53-69`仅在IDLE/COLLECT消费输入，64像素组齐后经过SEND/WAIT_ACK，ACK之后才能收下一组；等待期间只有一个320位输入弹性槽。`continuous_source_path.v:11,64-66`数据跨域FIFO为1024个8像素packet，即8192像素，连续有效DE约55.17微秒（4.27个1920像素有效行）。一旦当前帧已获准采集，隔帧丢弃不会降低该帧有效行内的瞬时像素速率。

在UI125MHz、PIX/RX148.5MHz与2200总像素/行条件下，一行时间为14.8148微秒，即1851.85UI拍。显示需要30个64像素读事务；若同一时间段还采集完整有效行，则还需30个写事务。忽略其它事务/调度开销，必要预算为 `30*Cw + 30*Cr <= 1851.85`，亦即平均 `Cw+Cr <= 61.728` UI拍。这里Cw/Cr应按实际串行engine服务占用测量，不能直接拿最大延迟322/332代入平均，也不能把整行空白完全当成额外免费预算。正常约32/32拍已经接近这一条件；偶发332拍的频度、相位和恢复余量决定是否失败。

UI_WRITE的8拍不能全部算作DDR全局空转：此时display不申请新命令，capture可使用engine；但它确实降低display自身连续申请速度。每行结束的双向mailbox同步也有开销；四行前瞻隐藏的是这类有限间隙和突发延迟。已知每128事务插入长等待通过、每16事务失败，只证明敏感度边界，不是实际PHY服务分布。

持续admitted/rejected增长且current_mask=0，不支持“全部银行credit永久死锁/engine永久硬故障”这一强命题。它仍兼容原因12短帧、13溢出、14协议关联或15写入完整性失败；历史peak1024不足以区分当前每次拒收原因。诊断先看四个原因的增量，再定位吞吐。

### 最小安全修复候选与可反证断言

1. **capture双assembly、仍最多一个inflight**：ACK等待时组装下一64像素，避免ACK后再花8拍重收组块。它减少producer空隙、提高可持续利用率；不是单纯加FIFO。但若真实读写总占用超预算，它只能推迟溢出。保持已接受burst payload不变；pending/inflight各自保留bank/gen/address；END必须等所有pending/inflight写ACK退休才发good terminal。不能只放宽consume而继续共用assembly/fill。
2. display下一块请求与本地8拍行RAM复制重叠，需要两块独立返回缓冲及严格buffer_free、row/gen/raw/bank关联，改动更大；先测它是否真的为瓶颈。不要盲目提高capture优先级或取消整行br屏蔽，已有旧变体分别暴露显示缺行/采集溢出。
3. 增FIFO/前瞻只吸收抖动；不能宣称修复持续负服务余量。普通拒帧也不宜直接触发自动复位，否则可能变成持续复位循环。

新增bench应在精确当前core+engine上扫描camera/display相位，分离“只capture+held display”与“再加背景B”，记录每帧FIFO满持续时间、reason12/13/14/15增量、W/R次数及延迟直方图、行完成相对deadline。若reason13不增而12增，应优先RX几何；若complete capture正常而PIX欠载，则优先显示服务。必须覆盖旧rsp与新accept同沿、END/BEGIN环绕、FIFO满、复位/时钟停启、迟到ACK不得推动新epoch游标、读写bank租用未结束不得回收。命令payload应在valid&&!ready期间稳定，good END对应所有写ACK退休，显示行只允许完整且tag完全匹配后可见。

### 新诊断候选独立审查

`D:/FPGA/output/live_repair_20261024/candidate/sources/video_correct_ddr_top.v:148-167`新增观察器仅驱动trace_data，未反馈epoch_fault/复位/仲裁/命令或银行选择。row06/07分别对应拒因12/13和14/15；row12是AW/AR次数，row13是定义为service_stage与WREADY/RVALID组合的压力拍数，不能冒充独立客户物理延迟；row16 bit79是同步的历史欠载锁存电平。UI计数随ui_rst清零，而快照随clocks_ready清零，恢复窗口应分段观察，不能跨恢复直接相减。

**P2：新row17扫描计数在应用复位时虚增。** top`:150`仅在clocks_ready低时清零，否则scan_start高就加一。display`:198,234`把scan_start直接定义为hc==0&&vc==0，`video_timing_vtc.v:39-57`在像素本地复位时保持两个坐标为0。因此clocks_ready仍高而应用/恢复pix复位期间，scan_start持续高，计数每PIX拍增加，不能当作真实扫描/HDMI持续运行证据。建议下一冻结版以scan_reset_n&&scan_start计数，并添加“clocks_ready高、pix本地复位持续多拍”的反例。已即时回报父代理，本审查没有修改编译中的candidate。
