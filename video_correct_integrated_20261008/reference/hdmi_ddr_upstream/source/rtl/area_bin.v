module area_bin #(
    parameter [7:0] OFFSET = 8'd5   // 小偏置，先从 5 开始试
)(
    input               video_clk,
    input               rst_n,

    input               matrix_de,
    input               matrix_vs,
    input       [7:0]   matrix11,
    input       [7:0]   matrix12,
    input       [7:0]   matrix13,
    input       [7:0]   matrix21,
    input       [7:0]   matrix22,
    input       [7:0]   matrix23,
    input       [7:0]   matrix31,
    input       [7:0]   matrix32,
    input       [7:0]   matrix33,

    output reg          area_bin_vs,
    output reg          area_bin_de,
    output reg          area_bin_data
);

    // 3x3求和，最大 9*255 = 2295，12bit足够
    reg [9:0]  row1_sum;
    reg [9:0]  row2_sum;
    reg [9:0]  row3_sum;
    reg [11:0] sum9_s1;

    // 中心像素流水
    reg [7:0] center_s0;
    reg [7:0] center_s1;
    reg [7:0] center_s2;

    // 局部均值
    reg [7:0] mean_s2;

    // 同步信号流水
    reg vs_s0, vs_s1, vs_s2;
    reg de_s0, de_s1, de_s2;

    // 12bit / 9 -> 8bit
    function [7:0] div9;
        input [11:0] din;
        begin
            div9 = din / 9;
        end
    endfunction

    // 均值 + 偏置，做饱和，避免超过255
    function [7:0] add_offset_sat;
        input [7:0] base;
        input [7:0] off;
        reg   [8:0] tmp;
        begin
            tmp = base + off;
            if(tmp > 9'd255)
                add_offset_sat = 8'hFF;
            else
                add_offset_sat = tmp[7:0];
        end
    endfunction

    always @(posedge video_clk or negedge rst_n) begin
        if(!rst_n) begin
            row1_sum      <= 10'd0;
            row2_sum      <= 10'd0;
            row3_sum      <= 10'd0;
            sum9_s1       <= 12'd0;

            center_s0     <= 8'd0;
            center_s1     <= 8'd0;
            center_s2     <= 8'd0;
            mean_s2       <= 8'd0;

            vs_s0         <= 1'b0;
            vs_s1         <= 1'b0;
            vs_s2         <= 1'b0;

            de_s0         <= 1'b0;
            de_s1         <= 1'b0;
            de_s2         <= 1'b0;

            area_bin_vs   <= 1'b0;
            area_bin_de   <= 1'b0;
            area_bin_data <= 1'b0;
        end
        else begin
            // stage0：三行求和，取中心像素
            row1_sum  <= matrix11 + matrix12 + matrix13;
            row2_sum  <= matrix21 + matrix22 + matrix23;
            row3_sum  <= matrix31 + matrix32 + matrix33;

            center_s0 <= matrix22;
            vs_s0     <= matrix_vs;
            de_s0     <= matrix_de;

            // stage1：9点总和
            sum9_s1   <= row1_sum + row2_sum + row3_sum;
            center_s1 <= center_s0;
            vs_s1     <= vs_s0;
            de_s1     <= de_s0;

            // stage2：求局部均值
            mean_s2   <= div9(sum9_s1);
            center_s2 <= center_s1;
            vs_s2     <= vs_s1;
            de_s2     <= de_s1;

            // stage3：比较中心像素和（局部均值 + 偏置）
            area_bin_vs   <= vs_s2;
            area_bin_de   <= de_s2;
            area_bin_data <= (center_s2 > add_offset_sat(mean_s2, OFFSET)) ? 1'b1 : 1'b0;
        end
    end

endmodule