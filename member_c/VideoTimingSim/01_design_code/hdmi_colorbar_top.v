`timescale 1ns/1ps
`default_nettype none

// MES2L676-100HP 板级 HDMI 彩条顶层。
//
// 27 MHz 板载时钟分别生成：
//   1. 148.5 MHz 像素时钟，供 1920x1080@60 视频扫描使用；
//   2. 10 MHz 配置时钟，供 MS7210 的 I2C 初始化使用。
//
// video_pll_27m_148m5 与 config_pll_27m_10m 已由 PDS 针对
// PG2L100H-6IFBG676 生成，保存在 01_design_code/ip。PDS 中该型号拆分选择为：
// Device=PG2L100H、Speed Grade=-6、Package=FBG676；字母 I 表示工业温度等级。
// 不能使用其他芯片或其他输入频率的 PLL 文件。
module hdmi_colorbar_top #(
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
    parameter [15:0] HDMI_RESET_CYCLES = 16'd10_000
)(
    input  wire        sys_clk_27m,
    input  wire        rst_n,

    output wire        hd_tx_pclk,
    output wire        hd_tx_vs,
    output wire        hd_tx_hs,
    output wire        hd_tx_de,
    output wire [23:0] hd_tx_data,

    output wire        hd_reset_n,
    output wire        hd_scl,
    inout  wire        hd_sda,
    output wire        hdmi_init_done
);

wire pix_clk;
wire cfg_clk;
wire video_pll_locked;
wire config_pll_locked;
wire video_reset_n;
wire video_hsync;
wire video_vsync;
wire video_de;
wire [23:0] video_rgb;

reg [15:0] hdmi_reset_count;

video_pll_27m_148m5 u_video_pll (
    .clkin1  (sys_clk_27m),
    .clkout0 (pix_clk),
    .lock    (video_pll_locked)
);

config_pll_27m_10m u_config_pll (
    .clkin1  (sys_clk_27m),
    .clkout0 (cfg_clk),
    .lock    (config_pll_locked)
);

// PLL 稳定后再保持 MS7210 复位一小段时间。
// 默认 10 MHz 下计数 10000 次，约为 1 ms。
always @(posedge cfg_clk or negedge rst_n) begin
    if (!rst_n)
        hdmi_reset_count <= 16'd0;
    else if (!config_pll_locked)
        hdmi_reset_count <= 16'd0;
    else if (hdmi_reset_count < HDMI_RESET_CYCLES)
        hdmi_reset_count <= hdmi_reset_count + 16'd1;
end

assign hd_reset_n = rst_n && config_pll_locked &&
                    (hdmi_reset_count == HDMI_RESET_CYCLES);

assign video_reset_n = rst_n && video_pll_locked;

video_top #(
    .H_SYNC       (H_SYNC),
    .H_BACK       (H_BACK),
    .H_ACTIVE     (H_ACTIVE),
    .H_FRONT      (H_FRONT),
    .V_SYNC       (V_SYNC),
    .V_BACK       (V_BACK),
    .V_ACTIVE     (V_ACTIVE),
    .V_FRONT      (V_FRONT),
    .HSYNC_ACTIVE (HSYNC_ACTIVE),
    .VSYNC_ACTIVE (VSYNC_ACTIVE)
) u_video_top (
    .clk         (pix_clk),
    .rst_n       (video_reset_n),
    .pattern_sel (2'b00),
    .hsync       (video_hsync),
    .vsync       (video_vsync),
    .de          (video_de),
    .rgb         (video_rgb)
);

ms7210_config u_ms7210_config (
    .cfg_clk   (cfg_clk),
    .reset_n   (hd_reset_n),
    .init_done (hdmi_init_done),
    .iic_scl   (hd_scl),
    .iic_sda   (hd_sda)
);

assign hd_tx_pclk = pix_clk;
assign hd_tx_vs = video_vsync;
assign hd_tx_hs = video_hsync;
assign hd_tx_de = video_de;
assign hd_tx_data = video_rgb;

endmodule

`default_nettype wire
