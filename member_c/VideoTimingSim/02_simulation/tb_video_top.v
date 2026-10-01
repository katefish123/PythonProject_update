`timescale 1ns/1ps

// 顶层集成检查：验证 VTC 与 TPG 通过 video_top 正确连接。
module tb_video_top;

localparam [11:0] H_SYNC         = 12'd2;
localparam [11:0] H_BACK         = 12'd2;
localparam [11:0] H_ACTIVE       = 12'd8;
localparam [11:0] H_FRONT        = 12'd2;
localparam [11:0] H_TOTAL        = H_SYNC + H_BACK + H_ACTIVE + H_FRONT;
localparam [11:0] H_ACTIVE_START = H_SYNC + H_BACK;
localparam [11:0] H_ACTIVE_END   = H_ACTIVE_START + H_ACTIVE;

localparam [11:0] V_SYNC         = 12'd1;
localparam [11:0] V_BACK         = 12'd1;
localparam [11:0] V_ACTIVE       = 12'd4;
localparam [11:0] V_FRONT        = 12'd1;
localparam [11:0] V_TOTAL        = V_SYNC + V_BACK + V_ACTIVE + V_FRONT;
localparam [11:0] V_ACTIVE_START = V_SYNC + V_BACK;
localparam [11:0] V_ACTIVE_END   = V_ACTIVE_START + V_ACTIVE;

localparam [1:0] PATTERN_COLOR_BARS = 2'b00;
localparam [1:0] PATTERN_SOLID      = 2'b01;
localparam [1:0] PATTERN_QUADRANTS = 2'b10;
localparam [1:0] PATTERN_BLACK     = 2'b11;
localparam [23:0] SOLID_COLOR      = 24'h00FFFF;

reg         clk;
reg         rst_n;
reg  [1:0]  pattern_sel;
wire        hsync;
wire        vsync;
wire        de;
wire [23:0] rgb;

integer checked_cycles;
integer test_failed;
reg [11:0] expected_h;
reg [11:0] expected_v;
reg expected_de;
reg [23:0] expected_rgb;

video_top #(
    .H_SYNC         (H_SYNC),
    .H_BACK         (H_BACK),
    .H_ACTIVE       (H_ACTIVE),
    .H_FRONT        (H_FRONT),
    .V_SYNC         (V_SYNC),
    .V_BACK         (V_BACK),
    .V_ACTIVE       (V_ACTIVE),
    .V_FRONT        (V_FRONT),
    .HSYNC_ACTIVE   (1'b1),
    .VSYNC_ACTIVE   (1'b1),
    .SOLID_COLOR    (SOLID_COLOR)
) dut (
    .clk         (clk),
    .rst_n       (rst_n),
    .pattern_sel (pattern_sel),
    .hsync       (hsync),
    .vsync       (vsync),
    .de          (de),
    .rgb         (rgb)
);

always #1 clk = ~clk;

task fail_test;
    input [8*96-1:0] reason;
    begin
        test_failed = 1;
        $display("TEST_FAIL_TOP: %0s", reason);
        $display("  h_cnt=%0d v_cnt=%0d pattern=%0b de=%0b rgb=%06h",
                 dut.h_cnt, dut.v_cnt, pattern_sel, de, rgb);
        $stop;
    end
endtask

task wait_position;
    input [11:0] target_h;
    input [11:0] target_v;
    begin
        while ((dut.h_cnt !== target_h) || (dut.v_cnt !== target_v))
            @(negedge clk);
        #0.1;
    end
endtask

task check_rgb;
    input [23:0] expected;
    input [8*64-1:0] description;
    begin
        #0.1;
        if (rgb !== expected)
            fail_test(description);
    end
endtask

initial begin
    clk            = 1'b0;
    rst_n          = 1'b0;
    pattern_sel    = PATTERN_COLOR_BARS;
    checked_cycles = 0;
    test_failed    = 0;
    expected_h     = 12'd0;
    expected_v     = 12'd0;

    repeat (4) @(negedge clk);
    #0.1 rst_n = 1'b1;

    // 消隐区必须输出黑色，并保持同步信号有效。
    wait_position(12'd0, 12'd0);
    if (de !== 1'b0 || rgb !== 24'h000000)
        fail_test("blanking output is not black");
    if (hsync !== 1'b1 || vsync !== 1'b1)
        fail_test("sync output is not connected from VTC");

    // 在同一个有效像素位置切换图案，确认 pattern_sel 已连接到 TPG。
    wait_position(12'd4, 12'd2);
    check_rgb(24'hFF0000, "color-bar top-left pixel is not red");

    pattern_sel = PATTERN_SOLID;
    check_rgb(SOLID_COLOR, "solid-color selection did not reach TPG");

    pattern_sel = PATTERN_QUADRANTS;
    check_rgb(24'hFF0000, "quadrant top-left pixel is not red");

    wait_position(12'd8, 12'd2);
    check_rgb(24'h00FF00, "quadrant top-right pixel is not green");

    wait_position(12'd4, 12'd4);
    check_rgb(24'h0000FF, "quadrant bottom-left pixel is not blue");

    wait_position(12'd8, 12'd4);
    check_rgb(24'hFFFFFF, "quadrant bottom-right pixel is not white");

    pattern_sel = PATTERN_BLACK;
    check_rgb(24'h000000, "reserved pattern selection is not black");

    // 再从 (0,0) 开始检查完整一帧。期望坐标独立计算，不能依赖 DUT 自己。
    pattern_sel = PATTERN_COLOR_BARS;
    wait_position(12'd0, 12'd0);
    expected_h = 12'd0;
    expected_v = 12'd0;

    repeat (H_TOTAL * V_TOTAL) begin
        @(negedge clk);
        #0.1;
        checked_cycles = checked_cycles + 1;

        if (expected_h == H_TOTAL - 12'd1) begin
            expected_h = 12'd0;
            if (expected_v == V_TOTAL - 12'd1)
                expected_v = 12'd0;
            else
                expected_v = expected_v + 12'd1;
        end
        else begin
            expected_h = expected_h + 12'd1;
        end

        if (dut.h_cnt !== expected_h)
            fail_test("h_cnt does not follow the configured line length");
        if (dut.v_cnt !== expected_v)
            fail_test("v_cnt does not follow the configured frame length");

        if (hsync !== (expected_h < H_SYNC))
            fail_test("hsync does not match the VTC counter");
        if (vsync !== (expected_v < V_SYNC))
            fail_test("vsync does not match the VTC counter");

        expected_de = (expected_h >= H_ACTIVE_START) &&
                      (expected_h <  H_ACTIVE_END)   &&
                      (expected_v >= V_ACTIVE_START) &&
                      (expected_v <  V_ACTIVE_END);

        if (de !== expected_de)
            fail_test("de does not match the active window");

        if (!expected_de)
            expected_rgb = 24'h000000;
        else if (expected_h < H_ACTIVE_START + H_ACTIVE / 4)
            expected_rgb = 24'hFF0000;
        else if (expected_h < H_ACTIVE_START + H_ACTIVE / 2)
            expected_rgb = 24'h00FF00;
        else if (expected_h < H_ACTIVE_START + H_ACTIVE * 3 / 4)
            expected_rgb = 24'h0000FF;
        else
            expected_rgb = 24'hFFFFFF;

        if (rgb !== expected_rgb)
            fail_test("rgb does not match the selected color-bar pixel");
    end

    if (checked_cycles != H_TOTAL * V_TOTAL)
        fail_test("top-level frame check did not cover one complete frame");
    if (dut.h_cnt !== 12'd0 || dut.v_cnt !== 12'd0)
        fail_test("top-level counters did not return to frame origin");

    $display("TEST_PASS_TOP: VTC and TPG top-level integration is correct");
    $display("  checked pixels: %0d", checked_cycles);
    $finish;
end

initial begin
    #10000;
    fail_test("simulation timeout");
end

endmodule
