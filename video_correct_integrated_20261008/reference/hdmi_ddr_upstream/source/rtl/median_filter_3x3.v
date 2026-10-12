//中值滤波 delay 3clk
module median_filter_3x3(
    input  wire       clk,
    input  wire       rst_n,

    input  wire       vsync_in,
    input  wire       hsync_in,
    input  wire       de_in,

    input  wire [7:0] data11,
    input  wire [7:0] data12,
    input  wire [7:0] data13,
    input  wire [7:0] data21,
    input  wire [7:0] data22,
    input  wire [7:0] data23,
    input  wire [7:0] data31,
    input  wire [7:0] data32,
    input  wire [7:0] data33,

    output reg  [7:0] target_data,
    output reg        vsync_out,
    output reg        hsync_out,
    output reg        de_out
);

// ----------------------------------------------------------
// 基本比较函数
// ----------------------------------------------------------
function [7:0] min2;
    input [7:0] a, b;
    begin
        min2 = (a < b) ? a : b;
    end
endfunction

function [7:0] max2;
    input [7:0] a, b;
    begin
        max2 = (a > b) ? a : b;
    end
endfunction

function [7:0] min3;
    input [7:0] a, b, c;
    begin
        min3 = min2(min2(a, b), c);
    end
endfunction

function [7:0] max3;
    input [7:0] a, b, c;
    begin
        max3 = max2(max2(a, b), c);
    end
endfunction

function [7:0] med3;
    input [7:0] a, b, c;
    reg   [7:0] x, y, z, t;
    begin
        x = a; y = b; z = c;
        if (x > y) begin t = x; x = y; y = t; end
        if (y > z) begin t = y; y = z; z = t; end
        if (x > y) begin t = x; x = y; y = t; end
        med3 = y;
    end
endfunction

function [23:0] sort3;
    input [7:0] a, b, c;
    reg   [7:0] x, y, z, t;
    begin
        x = a; y = b; z = c;
        if (x > y) begin t = x; x = y; y = t; end
        if (y > z) begin t = y; y = z; z = t; end
        if (x > y) begin t = x; x = y; y = t; end
        // {min, mid, max}
        sort3 = {x, y, z};
    end
endfunction

// ----------------------------------------------------------
// 9点中值
// 行内排序 -> max(min) / med(mid) / min(max) -> 再取中值
// ----------------------------------------------------------
function [7:0] median9;
    input [7:0] a1, a2, a3;
    input [7:0] b1, b2, b3;
    input [7:0] c1, c2, c3;

    reg [23:0] r0, r1, r2;
    reg [7:0]  r0_min, r0_mid, r0_max;
    reg [7:0]  r1_min, r1_mid, r1_max;
    reg [7:0]  r2_min, r2_mid, r2_max;
    reg [7:0]  max_of_mins;
    reg [7:0]  med_of_mids;
    reg [7:0]  min_of_maxs;
    begin
        r0 = sort3(a1, a2, a3);
        r1 = sort3(b1, b2, b3);
        r2 = sort3(c1, c2, c3);

        r0_min = r0[23:16];
        r0_mid = r0[15:8];
        r0_max = r0[7:0];

        r1_min = r1[23:16];
        r1_mid = r1[15:8];
        r1_max = r1[7:0];

        r2_min = r2[23:16];
        r2_mid = r2[15:8];
        r2_max = r2[7:0];

        max_of_mins = max3(r0_min, r1_min, r2_min);
        med_of_mids = med3(r0_mid, r1_mid, r2_mid);
        min_of_maxs = min3(r0_max, r1_max, r2_max);

        median9 = med3(max_of_mins, med_of_mids, min_of_maxs);
    end
endfunction

// ----------------------------------------------------------
// 3拍流水：保证官方风格的 fixed delay 3clk
// ----------------------------------------------------------
reg [7:0] median_d0, median_d1, median_d2;
reg       vs_d0, vs_d1, vs_d2;
reg       hs_d0, hs_d1, hs_d2;
reg       de_d0, de_d1, de_d2;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        median_d0 <= 8'd0;
        median_d1 <= 8'd0;
        median_d2 <= 8'd0;

        vs_d0 <= 1'b0;
        vs_d1 <= 1'b0;
        vs_d2 <= 1'b0;

        hs_d0 <= 1'b0;
        hs_d1 <= 1'b0;
        hs_d2 <= 1'b0;

        de_d0 <= 1'b0;
        de_d1 <= 1'b0;
        de_d2 <= 1'b0;

        target_data <= 8'd0;
        vsync_out   <= 1'b0;
        hsync_out   <= 1'b0;
        de_out      <= 1'b0;
    end
    else begin
        // stage0
        median_d0 <= median9(
            data11, data12, data13,
            data21, data22, data23,
            data31, data32, data33
        );
        vs_d0 <= vsync_in;
        hs_d0 <= hsync_in;
        de_d0 <= de_in;

        // stage1
        median_d1 <= median_d0;
        vs_d1 <= vs_d0;
        hs_d1 <= hs_d0;
        de_d1 <= de_d0;

        // stage2
        median_d2 <= median_d1;
        vs_d2 <= vs_d1;
        hs_d2 <= hs_d1;
        de_d2 <= de_d1;

        // output
        target_data <= median_d2;
        vsync_out   <= vs_d2;
        hsync_out   <= hs_d2;
        de_out      <= de_d2;
    end
end

endmodule