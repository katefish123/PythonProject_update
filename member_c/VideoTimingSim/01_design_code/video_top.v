`timescale 1ns/1ps
`default_nettype none

// 视频顶层：统一配置并连接 VTC 时序控制器与 TPG 测试图案发生器。
module video_top #(
    parameter [11:0] H_SYNC   = 12'd44,
    parameter [11:0] H_BACK   = 12'd148,
    parameter [11:0] H_ACTIVE = 12'd1920,
    parameter [11:0] H_FRONT  = 12'd88,
    parameter [11:0] V_SYNC   = 12'd5,
    parameter [11:0] V_BACK   = 12'd36,
    parameter [11:0] V_ACTIVE = 12'd1080,
    parameter [11:0] V_FRONT  = 12'd4,
    parameter        HSYNC_ACTIVE = 1'b1,
    parameter        VSYNC_ACTIVE = 1'b1,
    parameter [23:0] SOLID_COLOR  = 24'hFFFFFF
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [1:0]  pattern_sel,

    output wire        hsync,
    output wire        vsync,
    output wire        de,
    output wire [23:0] rgb
);

localparam [11:0] H_ACTIVE_START = H_SYNC + H_BACK;
localparam [11:0] V_ACTIVE_START = V_SYNC + V_BACK;

wire [11:0] h_cnt;
wire [11:0] v_cnt;

video_timing_vtc #(
    .H_SYNC         (H_SYNC),
    .H_BACK         (H_BACK),
    .H_ACTIVE       (H_ACTIVE),
    .H_FRONT        (H_FRONT),
    .V_SYNC         (V_SYNC),
    .V_BACK         (V_BACK),
    .V_ACTIVE       (V_ACTIVE),
    .V_FRONT        (V_FRONT),
    .HSYNC_ACTIVE   (HSYNC_ACTIVE),
    .VSYNC_ACTIVE   (VSYNC_ACTIVE)
) u_vtc (
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
    .V_ACTIVE       (V_ACTIVE),
    .SOLID_COLOR    (SOLID_COLOR)
) u_tpg (
    .h_cnt       (h_cnt),
    .v_cnt       (v_cnt),
    .de          (de),
    .pattern_sel (pattern_sel),
    .rgb         (rgb)
);

endmodule

`default_nettype wire
