# FIFO 最小实验学习记录

本实验使用已有的 sync_fifo.v 学习模型，8 位数据、16 项容量、单时钟。
它不是 Pango FIFO IP，也不涉及 HDMI、DDR 或板卡引脚。正式空顶层未修改。
工具链约定：PDS 建工程与实现，Pango ADS 综合，ModelSim 仿真。

## 今天的学习顺序

1. 用现有模型理解先进先出，观察四次写入和四次读出。
2. 观察读空、写满、同时读写和复位行为。
3. 在 PDS 中配置适用于 Logos-2 的现成 FIFO IP，检查生成的接口和仿真文件。
4. 按实际 IP 的复位、读取模式和延迟调整连接与 testbench，再用 ModelSim 验证。

第 3、4 项尚未完成。不要直接把学习模型的端口、空满边界策略或读出延迟套到厂商 IP。

## 第一步 基础波形

打开 ModelSim，在 Transcript 输入：

```tcl
do C:/D/FPGA/demo/Projects/sync_fifo_demo/sim/basic/run_gui.do
```

脚本会编译唯一一份 RTL 和基础 testbench，添加信号，运行至 146 ns，并保留窗口。
不要将 testbench 添加到 PDS 的综合设计源文件中。

FIFO 像排队：先放入的数据先取出。din 是准备放入的数据；dout 是最近一次有效读取的结果。
wr_en、rd_en 是请求；能否真正操作由上升沿之前的 full、empty 判断。

| 信号 | 本模型的含义 |
| --- | --- |
| clk | 上升沿处理读写；TB 周期 10 ns，仅为仿真设置 |
| rst_n | 0 时复位；count、指针、dout 清零 |
| wr_en 与 din | wr_en=1 且 full=0 才写入 din |
| rd_en 与 dout | rd_en=1 且 empty=0 才读取，上升沿后更新 dout |
| count | 尚未读出的项数，范围 0 到 16 |
| empty | count=0 时为 1 |
| full | count=16 时为 1 |

din、dout 显示为十六进制；count 和指针显示为十进制。
下面的值应在对应上升沿更新后观察：

| 上升沿时间 | 操作 | count | dout |
| --- | --- | --- | --- |
| 35 ns | 写入 11 | 1 | 00 |
| 45 ns | 写入 22 | 2 | 00 |
| 55 ns | 写入 33 | 3 | 00 |
| 65 ns | 写入 44 | 4 | 00 |
| 75、85 ns | 暂停读写 | 4 | 00 |
| 95 ns | 读出第一项 | 3 | 11 |
| 105 ns | 读出第二项 | 2 | 22 |
| 115 ns | 读出第三项 | 1 | 33 |
| 125 ns | 读出第四项 | 0 | 44 |

125 ns 后 empty=1。dout 保留 44 并不表示 FIFO 内还有数据。
只有有效读对应的输出才是一笔新数据；本模型未提供单独的 dout_valid。
Transcript 应出现 PASS: basic FIFO simulation，errors=0。

## 第二步 边界波形

基础波形看懂后，在 Transcript 输入：

```tcl
do C:/D/FPGA/demo/Projects/sync_fifo_demo/sim/boundary/run_gui.do
```

先运行 600 ns，观察定向测试；完整执行再输入：

```tcl
run -all
```

本模型按上升沿之前的空满状态接受请求：

| 原状态 | 请求 | 接受的操作 | 数量变化 |
| --- | --- | --- | --- |
| 空 | 只读 | 无 | 保持 0 |
| 满 | 只写 | 无 | 保持 16 |
| 空 | 同时读写 | 只写 | 0 到 1 |
| 满 | 同时读写 | 只读 | 16 到 15 |
| 非空且非满 | 同时读写 | 两个都接受 | 不变 |

FIFO 只负责按顺序暂存数据；上游若忽略 full 仍持续送数，被拒绝的数据会丢失。
单时钟模型不能用于两个不同时钟之间直接传数据；跨域时需要合适的异步 FIFO。

## 助手独立复验记录

2026-10-05 使用本机 ModelSim SE-64 2020.4 重新编译并执行已有两份 testbench。

- 基础：PASS: basic FIFO simulation；146 ns 结束。
- 边界及随机：PASS: 1124 checks；11266 ns 结束。
- 两次编译及仿真报告均为 Errors: 0、Warnings: 0。
- 日志分别位于 sim/basic/modelsim_check.log、sim/boundary/modelsim_check.log。
- 复验入口为 sim/check_modelsim.ps1；GUI 波形脚本供用户跟随教学运行。
- 本次未验证 PDS 综合、资源映射、板级时序或上板功能；未生成 Pango FIFO IP。

自动检查通过与用户理解验收分别记录。能解释顺序、满空、读出时刻之后，再勾选学习目标。
