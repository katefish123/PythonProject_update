`timescale 1ns/1ps

// TPG（Test Pattern Generator）：根据当前像素坐标产生可切换的测试图案。
// pattern_sel：00=竖彩条，01=纯色，10=四象限，11=保留（黑色）。
module test_pattern_generator_tpg #(
    parameter [11:0] H_ACTIVE_START = 12'd192,
    parameter [11:0] H_ACTIVE       = 12'd1920,
    parameter [11:0] V_ACTIVE_START = 12'd41,
    parameter [11:0] V_ACTIVE       = 12'd1080,
    parameter [23:0] SOLID_COLOR    = 24'hFFFFFF
)(
    input  wire [11:0] h_cnt,
    input  wire [11:0] v_cnt,
    input  wire        de,
    input  wire [1:0]  pattern_sel,
    output reg  [23:0] rgb
);

localparam [1:0] PATTERN_COLOR_BARS = 2'b00;
localparam [1:0] PATTERN_SOLID      = 2'b01;
localparam [1:0] PATTERN_QUADRANTS = 2'b10;

localparam [11:0] H_QUARTER = H_ACTIVE >> 2;
localparam [11:0] H_HALF    = H_ACTIVE >> 1;
localparam [11:0] V_HALF    = V_ACTIVE >> 1;

localparam [11:0] H_BAR_1_END = H_ACTIVE_START + H_QUARTER;
localparam [11:0] H_BAR_2_END = H_ACTIVE_START + H_HALF;
localparam [11:0] H_BAR_3_END = H_ACTIVE_START + H_HALF + H_QUARTER;
localparam [11:0] H_MIDDLE    = H_ACTIVE_START + H_HALF;
localparam [11:0] V_MIDDLE    = V_ACTIVE_START + V_HALF;

always @(*) begin
    rgb = 24'h000000;

    if (de) begin
        case (pattern_sel)
            PATTERN_COLOR_BARS: begin
                if (h_cnt < H_BAR_1_END)
                    rgb = 24'hFF0000;
                else if (h_cnt < H_BAR_2_END)
                    rgb = 24'h00FF00;
                else if (h_cnt < H_BAR_3_END)
                    rgb = 24'h0000FF;
                else
                    rgb = 24'hFFFFFF;
            end

            PATTERN_SOLID: begin
                rgb = SOLID_COLOR;
            end

            PATTERN_QUADRANTS: begin
                if (v_cnt < V_MIDDLE) begin
                    if (h_cnt < H_MIDDLE)
                        rgb = 24'hFF0000;
                    else
                        rgb = 24'h00FF00;
                end
                else begin
                    if (h_cnt < H_MIDDLE)
                        rgb = 24'h0000FF;
                    else
                        rgb = 24'hFFFFFF;
                end
            end

            default: begin
                rgb = 24'h000000;
            end
        endcase
    end
end

endmodule
