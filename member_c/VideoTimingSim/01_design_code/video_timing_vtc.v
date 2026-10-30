`timescale 1ns/1ps
`default_nettype none

// VTC（Video Timing Controller）：只负责扫描坐标、同步信号和有效区信号。
module video_timing_vtc #(
    parameter [11:0] H_SYNC   = 12'd44,
    parameter [11:0] H_BACK   = 12'd148,
    parameter [11:0] H_ACTIVE = 12'd1920,
    parameter [11:0] H_FRONT  = 12'd88,
    parameter [11:0] V_SYNC   = 12'd5,
    parameter [11:0] V_BACK   = 12'd36,
    parameter [11:0] V_ACTIVE = 12'd1080,
    parameter [11:0] V_FRONT  = 12'd4,
    parameter        HSYNC_ACTIVE = 1'b1,
    parameter        VSYNC_ACTIVE = 1'b1
)(
    input wire clk,
    input wire rst_n,

    output reg [11:0] h_cnt,
    output reg [11:0] v_cnt,

    output wire hsync,
    output wire vsync,
    output wire de
);

localparam [11:0] H_TOTAL        = H_SYNC + H_BACK + H_ACTIVE + H_FRONT;
localparam [11:0] H_ACTIVE_START = H_SYNC + H_BACK;
localparam [11:0] H_ACTIVE_END   = H_ACTIVE_START + H_ACTIVE;
localparam [11:0] V_TOTAL        = V_SYNC + V_BACK + V_ACTIVE + V_FRONT;
localparam [11:0] V_ACTIVE_START = V_SYNC + V_BACK;
localparam [11:0] V_ACTIVE_END   = V_ACTIVE_START + V_ACTIVE;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        h_cnt <= 12'd0;
    else if (h_cnt == H_TOTAL - 12'd1)
        h_cnt <= 12'd0;
    else
        h_cnt <= h_cnt + 12'd1;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        v_cnt <= 12'd0;
    else if (h_cnt == H_TOTAL - 12'd1) begin
        if (v_cnt == V_TOTAL - 12'd1)
            v_cnt <= 12'd0;
        else
            v_cnt <= v_cnt + 12'd1;
    end
end

assign de = (h_cnt >= H_ACTIVE_START && h_cnt < H_ACTIVE_END) &&
            (v_cnt >= V_ACTIVE_START && v_cnt < V_ACTIVE_END);

assign hsync = (h_cnt < H_SYNC) ? HSYNC_ACTIVE : !HSYNC_ACTIVE;
assign vsync = (v_cnt < V_SYNC) ? VSYNC_ACTIVE : !VSYNC_ACTIVE;

endmodule

`default_nettype wire
