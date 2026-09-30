`timescale 1ns/1ps

// 正式参数检查：直接使用 video_timing_vtc 的默认 1920x1080@60 参数。
// 本文件不用于观察细节波形；教学波形仍使用 tb_video_timing.v。
module tb_video_timing_1080p;

localparam [11:0] H_SYNC         = 12'd44;
localparam [11:0] H_BACK         = 12'd148;
localparam [11:0] H_ACTIVE       = 12'd1920;
localparam [11:0] H_FRONT        = 12'd88;
localparam [11:0] H_TOTAL        = 12'd2200;
localparam [11:0] H_ACTIVE_START = H_SYNC + H_BACK;
localparam [11:0] H_ACTIVE_END   = H_ACTIVE_START + H_ACTIVE;

localparam [11:0] V_SYNC         = 12'd5;
localparam [11:0] V_BACK         = 12'd36;
localparam [11:0] V_ACTIVE       = 12'd1080;
localparam [11:0] V_FRONT        = 12'd4;
localparam [11:0] V_TOTAL        = 12'd1125;
localparam [11:0] V_ACTIVE_START = V_SYNC + V_BACK;
localparam [11:0] V_ACTIVE_END   = V_ACTIVE_START + V_ACTIVE;

reg clk;
reg rst_n;
reg [1:0] pattern_sel;

wire [11:0] h_cnt;
wire [11:0] v_cnt;
wire        hsync;
wire        vsync;
wire        de;
wire [23:0] rgb;

reg [11:0] expected_h;
reg [11:0] expected_v;
integer checked_cycles;
integer checked_lines;
reg     expected_de;
reg [23:0] expected_rgb;

video_timing_vtc dut (
    .clk   (clk),
    .rst_n (rst_n),
    .h_cnt (h_cnt),
    .v_cnt (v_cnt),
    .hsync (hsync),
    .vsync (vsync),
    .de    (de)
);

test_pattern_generator_tpg #(
    .H_ACTIVE_START (H_ACTIVE_START),
    .H_ACTIVE       (H_ACTIVE),
    .V_ACTIVE_START (V_ACTIVE_START),
    .V_ACTIVE       (V_ACTIVE)
) tpg (
    .h_cnt       (h_cnt),
    .v_cnt       (v_cnt),
    .de          (de),
    .pattern_sel (pattern_sel),
    .rgb         (rgb)
);

task fail_test;
    input [8*96-1:0] reason;
    begin
        $display("TEST_FAIL_1080P: %0s", reason);
        $display("  cycle=%0d expected=(%0d,%0d) actual=(%0d,%0d)",
                 checked_cycles, expected_h, expected_v, h_cnt, v_cnt);
        $finish;
    end
endtask

initial begin
    clk            = 1'b0;
    rst_n          = 1'b0;
    pattern_sel    = 2'b00;
    expected_h     = 12'd0;
    expected_v     = 12'd0;
    checked_cycles = 0;
    checked_lines  = 0;

    // 让复位覆盖多个时钟边沿，再在下降沿之后释放，避免仿真竞争。
    repeat (4) @(negedge clk);
    #0.1 rst_n = 1'b1;
end

// 正式检查关注每个像素时钟之间的逻辑关系，因此使用较短的仿真周期。
always #1 clk = ~clk;

// 在下降沿取样，确保设计在上升沿产生的新值已经稳定。
always @(negedge clk) begin
    if (!rst_n) begin
        expected_h     = 12'd0;
        expected_v     = 12'd0;
        checked_cycles = 0;
        checked_lines  = 0;
    end
    else begin
        if (expected_h == H_TOTAL - 12'd1) begin
            expected_h = 12'd0;
            checked_lines = checked_lines + 1;

            if (expected_v == V_TOTAL - 12'd1)
                expected_v = 12'd0;
            else
                expected_v = expected_v + 12'd1;
        end
        else begin
            expected_h = expected_h + 12'd1;
        end

        checked_cycles = checked_cycles + 1;

        if (h_cnt !== expected_h)
            fail_test("h_cnt did not follow the 0..2199 sequence");

        if (v_cnt !== expected_v)
            fail_test("v_cnt changed at the wrong pixel or did not wrap");

        if (hsync !== (expected_h < H_SYNC))
            fail_test("hsync active range is not h_cnt=0..43");

        if (vsync !== (expected_v < V_SYNC))
            fail_test("vsync active range is not v_cnt=0..4");

        expected_de = (expected_h >= H_ACTIVE_START) &&
                      (expected_h <  H_ACTIVE_END)   &&
                      (expected_v >= V_ACTIVE_START) &&
                      (expected_v <  V_ACTIVE_END);

        if (de !== expected_de)
            fail_test("de active area does not match 1920x1080");

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
            fail_test("rgb value is wrong for the current active-area quarter");

        if ((expected_h == 12'd0) && (expected_v == 12'd0)) begin
            if (checked_cycles != 2475000)
                fail_test("frame length is not 2200*1125 pixel clocks");

            if (checked_lines != 1125)
                fail_test("frame does not contain exactly 1125 lines");

            $display("TEST_PASS_1080P");
            $display("  checked pixels: %0d", checked_cycles);
            $display("  checked lines : %0d", checked_lines);
            $display("  timing        : 2200 x 1125 totals, 1920 x 1080 active");
            $finish;
        end
    end
end

// 防止逻辑异常时仿真无限运行。
initial begin
    #6000000;
    fail_test("simulation timeout before one complete frame");
end

endmodule
