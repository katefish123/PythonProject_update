# 四行前瞻候选的物理时序记录

此记录不授予烧录资格。place111候选不包含下述ACK授权寄存；独立credit候选已经包含该改动并在完整PDS编译中。最终报告和`qualify_lookahead.py`是放行依据。

## 已观察到的路径

`b_lens_board_lookahead_place111_20261023/build/place_route/route_constraint_ite_1/video_correct_ddr_top.rtr`为内部第一轮报告：DDR同域建立时间65个失败端点、最差-0.571ns。最长示例从`core/stream_path/writer/acknowledgement_fifo/f`经writer命令有效、仲裁、UI选择和engine地址合法性判断，到`engine/fault_reason_reg[1]`。共8级组合逻辑，布线占6.294ns（78.951%）。这不是显示读RAM选择器的关键路径证据。工具仍继续自动迭代，不能把内部报告当作最终结果。

之前固定布局重新布线的三个迭代均失败；第一次完整四行候选最终最差-0.125ns。失败文件保留，禁止以生成了码流为由交付。

## 若最终仍失败：优先验证的单变量结构

writer当前的`cmd_valid`实时依赖ACK FIFO的`!afull`。可在独立候选中验证把ACK空位授权登记为一个UI时钟寄存器：在`!ui_live`分支清零，工作时每拍登记`!afull && !ack_push`，用该许可替换`cmd_valid`里的实时`!afull`。所有其他源帧、B算法、银行归属、时钟和约束保持不变。

独立只读评审认为该假设在现有契约下信用安全：ACK只有一个写入者、最多一个inflight、命令接受前预留一个ACK空位；唯一可能让FIFO从非满变满的ACK写入在同拍清除许可。已有inflight时禁止再issue，因此旧响应和下一命令不能同拍接受；新命令与零延迟响应同拍时，ACK仍取当前命令epoch并清许可。命令被背压时不存在ACK写入，许可不会正常撤销。共同硬复位及现有满时写入断言必须保留。

独立副本已实现该结构，`writer_credit_pipeline2_20261023`在相同扩展激励下分别检查旧writer和寄存许可writer：随机异步时钟、命令背压时地址/数据稳定、零延迟响应、停止源时钟后ACK满/恢复、abort/epoch与共同复位均通过，编译运行零错误/警告。`credit_shared_raw128_20261023`同稀疏等待完整共享RAW模型已核对4,147,200像素通过。完整校正两幅核对14,515,200像素、六幅连续变化核对64,281,600显示像素均通过；模型10.0122128张新校正图/秒，非实板FPS。第一次测试工具因声明顺序编译失败，记录保留在`writer_credit_pipeline_20261023`，未计入通过证据。

该结构未加入正在编译的place111候选，尚无物理时序资格。ACK后可能多一个UI拍重新授权，必须重测新结果率。许可寄存器自身仍受ACK/issue/ready逻辑影响，不能预先声称时序一定改善。

place111独立最终时序仍有15个DDR建立时间端点失败、最差-0.399ns，已排除交付；因此继续验证credit候选的完整物理实现。所有最终时序及交付门槛通过后才交给烧录窗口。


## 2026-10-23 merged payload implementation: first report

Current source-frozen candidate: `D:/FPGA/output/b_lens_board_payload_20261023`. Positive full-chain tests pass: RAW 4,147,200 pixels, corrected 14,515,200 pixels and six varied published frames over 64,281,600 displayed pixels. The six-frame model gives 10.012212837 corrected publications/sec; this is not a board rate. Dense hypothetical long-wait service still produces a missing line, retained as a known limit. Twenty evidence-gate tests pass. No current full repair is released or programmed.

First route has three DDR same-domain failing endpoints (-0.314 ns), and 27 DDR-to-PHY0 failing endpoints (-0.626 ns); PIX same-domain +0.469 ns. Cache s_y[2]/l_y1[5] to l_missing use 128-fanout coordinate nets. Writer inflight/UI grant/engine response_kind also fails. Previous wdata_hold and cache victim/tag failures do not reappear in the listed failing paths.

PHY CA calibration selection to address IOL has 88-91% data-route delay. FDC and IP RTL are identical to qualified statusfix; same related-clock exception applied, skew differs by 2 ps. No false paths or clock relaxation. Three invalid adj_addr load names rejected in pds_console.log lines 25275-25282. Official Route Constraint Editor supports whole-net priority and add_constraint RCF input; DDR UG calls for its generated clock-gate RCF. Current implementation left unmodified. If final timing fails, verify actual mapped objects and accepted RCF loading before targeted placement.


## Selected complete implementation

The third internal route and independent final report both pass all 10 sections / 100 timing rows; minimum +0.015 ns. Complete PDS Generate Bitstream exited successfully. The exact-source qualification helper passed and released bit SHA256 c12913626e11352f5fbeefe468c63bfd52718209212561d4ca727ad741f65c22. No physical image acceptance is implied. The four-coordinate fanout experiment was not selected and its source-only child must not be programmed as this release. The three rejected automatic RCF loads remain recorded as tool diagnostics; final timing was achieved without editing or relaxing their constraints.
