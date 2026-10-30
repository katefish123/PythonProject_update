`timescale 1ns/1ps

// TPG 独立检查：不依赖 VTC，直接给出坐标与 de，验证每种图案。
module tb_tpg_patterns;

localparam [1:0] PATTERN_COLOR_BARS = 2'b00;
localparam [1:0] PATTERN_SOLID      = 2'b01;
localparam [1:0] PATTERN_QUADRANTS = 2'b10;

reg  [11:0] h_cnt;
reg  [11:0] v_cnt;
reg         de;
reg  [1:0]  pattern_sel;
wire [23:0] rgb;

test_pattern_generator_tpg #(
    .H_ACTIVE_START (12'd4),
    .H_ACTIVE       (12'd8),
    .V_ACTIVE_START (12'd2),
    .V_ACTIVE       (12'd4),
    .SOLID_COLOR    (24'h00FFFF)
) dut (
    .h_cnt       (h_cnt),
    .v_cnt       (v_cnt),
    .de          (de),
    .pattern_sel (pattern_sel),
    .rgb         (rgb)
);

task check_rgb;
    input [23:0] expected;
    input [8*48-1:0] description;
    begin
        #1;
        if (rgb !== expected) begin
            $display("TEST_FAIL_TPG: %0s", description);
            $display("  h_cnt=%0d v_cnt=%0d de=%0b pattern=%0b", h_cnt, v_cnt, de, pattern_sel);
            $display("  expected=%06h actual=%06h", expected, rgb);
            $finish;
        end
    end
endtask

initial begin
    h_cnt      = 12'd0;
    v_cnt      = 12'd0;
    de         = 1'b0;
    pattern_sel = PATTERN_COLOR_BARS;

    check_rgb(24'h000000, "blanking area must be black");

    de = 1'b1;
    h_cnt = 12'd4;  check_rgb(24'hFF0000, "color bar 1 must be red");
    h_cnt = 12'd6;  check_rgb(24'h00FF00, "color bar 2 must be green");
    h_cnt = 12'd8;  check_rgb(24'h0000FF, "color bar 3 must be blue");
    h_cnt = 12'd10; check_rgb(24'hFFFFFF, "color bar 4 must be white");

    pattern_sel = PATTERN_SOLID;
    h_cnt = 12'd7;
    v_cnt = 12'd3;
    check_rgb(24'h00FFFF, "solid pattern must use SOLID_COLOR");

    pattern_sel = PATTERN_QUADRANTS;
    h_cnt = 12'd4; v_cnt = 12'd2; check_rgb(24'hFF0000, "top-left quadrant must be red");
    h_cnt = 12'd8; v_cnt = 12'd2; check_rgb(24'h00FF00, "top-right quadrant must be green");
    h_cnt = 12'd4; v_cnt = 12'd4; check_rgb(24'h0000FF, "bottom-left quadrant must be blue");
    h_cnt = 12'd8; v_cnt = 12'd4; check_rgb(24'hFFFFFF, "bottom-right quadrant must be white");

    pattern_sel = 2'b11;
    check_rgb(24'h000000, "reserved pattern must be black");

    $display("TEST_PASS_TPG: all pattern modes are correct");
    $finish;
end

endmodule
