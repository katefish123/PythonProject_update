# V5C 硬件验收交接

本任务未烧板、未操作 OBS。冻结 V4S 仍保留。V5C最终时序全部约束通过，快慢两个工艺角100条汇总记录均无失败端点。真实硬件验收尚未完成。

交付文件在 `release_candidate_v5c/`：video_correct_ddr_top.sbit、同名smsk、V5C_PDS_source_project.zip 和 receipt.json。sbit SHA256：`d249b55e01199b7d6106ca009b9ca562273a1e502e13d5bfb13d761a95bfcbda`；smsk：`76381c3a9be2c65d325536216a886df953ce13b0fe7fd0819412caefdd1fabb9`。工程包包含146个冻结输入、原本机PDS工程、相对路径重建Tcl、最终时序及烧录文件；完整校验见 evidence/v5c/implementation.json。

实现目录 `D:/FPGA/output/c_board_next_v5c_20261016`，sources 为冻结输入，build 保存 PDS 工程与报告。整板清单为 `board/source_manifest.json`（145个设计文件、1个约束），应用清单 integration/sources.json 不能代替它。

## 操作与验收

- KEY1 松开为 RAW，按住请求 CORRECTED；KEY2 保留 nearest 选择，默认松开 bilinear。切换等待完整结果及显示确认，不覆盖正在显示的源缓存。
- RAW 完整1920×1080、逐像素1:1。校正有效765×1080，存储768×1080，左1右2列补黑、居中输出、保持目标比例。HEX及顶部状态会覆盖部分RAW画面，底层DDR源图仍完整保存。
- CORRECTED 只接受合法四色角标页：红左上、绿右上、黄右下、蓝左下。使用 `geometry/fixtures/matching_four_color_test_page.pdf`；不保证任意黑色角标识别。
- 超过100ms没换图显示 HELD LAST FRAME；RECOVERING DDR 表示共同复位/重训，最多自动三次；RETRY LIMIT 表示耗尽，需手动复位。HDMI配置和视频PLL不随内存恢复反复配置。
- 先测RAW相机源图及移动物体，再测四色页几何与内部网格，最后测重连及长期运行。实际新图速率数00行显示ID的**变化次数**，不能用ID差值、03发布请求数或OBS扫描帧率代替。

仿真 RAW 约30张新图/秒仅是数字模型结果。真实相机吞吐、模糊/OVER/PHY根因以及60张新校正图/秒仍未证明解决。

## HEX 诊断

行号为十六进制，后面20位十六进制数据（80bit）。下表有效字段按高→低列出，未说明高位补0。00行取实际PIX显示元数据；其他观察字段是有延迟的异步快照。已完成校正快照可能与当前RAW不是同一帧。

|行|有效字段，高→低|
|---|---|
|00|显示帧号32、地址28、RAW1、bank1、有效1|
|01|物理输入帧数32、接纳帧数32|
|02|丢弃帧数32、拒绝帧数32|
|03|RAW发布请求数32、CORR发布请求数32|
|04|PROC确认显示帧号32、年龄毫秒32|
|05|FIFO峰值11、已完成CORR帧号32、恢复记录11|
|06|TL、TR，各24位|
|07|BR、BL，各24位|
|08|H0、H1，各40位|
|09|H2、H3|
|0A|H4、H5|
|0B|H6、H7|
|0C|已完成结果地址28、H8 40|
|0D|当前与首次故障位域，见下文|
|0E|最大AW等待32、最大首W等待32|
|0F|最大W间隙32、最大首R等待32|
|10|最大R间隙32、最大命令等待32|
|11|首次UI tick48、首次阶段4、首次mask5|
|12|已完成校正的源地址28|
|13|首次事件最大AW等待32、首W等待32|
|14|首次事件最大W间隙32、首R等待32|
|15|首次事件最大R间隙32、命令等待32|
|16|首次FIFO有效1、首次峰值11、首次源事件有效1、源原因4、PROC tick48|
|17|首次源事件到达UI的tick48|

H为带符号40位补码Q24：先转有符号数，再除2^24。角点每24位，高12位x、低12位y（每个坐标3位十六进制）。地址以32位像素字计，不是字节。恢复记录低3位为状态（0训练、1运行、2复位保持、3稳定等待、4停止），高8位重试次数。服务计数单位UI周期；PROC和UI时间戳不能直接相减。FIFO峰值采用保守跨域观测，首次值是PROC首次识别源故障时已收到的峰值，不能视作故障同周期精确采样。DQS原始采样不支持，常0不能作为硬件证据。

0D从低位开始：epoch[0]、first_valid[1]、阶段[5:2]、当前engine原因[9:6]、首次mask[14:10]、首次kind[17:15]、首次raw[21:18]、首次source[25:22]、当前mask[30:26]、当前kind[33:31]、当前raw[37:34]、当前source[41:38]、首次engine原因[45:42]。

mask bit0..4 = source/engine/PHY/ALIGN/self；kind 0无、1source、2engine、3PHY、4ALIGN、5self；服务阶段0空闲、1AW、2W、3AR、4R。首次历史在自动恢复后保留，手动复位清除；历史ALIGN不能替代当前错误。ALIGN表示DDR IP受保护的DQS读切片对齐故障，不是应用地址对齐错误。

## 复现

依次运行 display/prepare_display.py、build_integration.py、prepare_pipeline_fixtures.py、build_board.py。测试 run_integration.ps1 使用新后缀，RAW加 `-Native -Frames 12`，CORRECTED加 `-Native -Corrected -Frames 6`；board/run_recovery.ps1 为整板恢复测试。collect_v5c.py 核对冻结输入、实际编译源SHA与日志。旧 collect_evidence.py 只用于历史应用层证据。
