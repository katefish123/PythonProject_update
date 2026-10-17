`timescale 1ns / 1ps
module HDMI_IN_DDR3_YCbCr_top#(
    parameter MEM_ROW_ADDR_WIDTH   = 15,
    parameter MEM_COL_ADDR_WIDTH   = 10,
    parameter MEM_BADDR_WIDTH      = 3,
    parameter MEM_DQ_WIDTH         = 32,
    parameter MEM_DQS_WIDTH        = 32/8
)(
    input                                sys_clk,
    input                                clk_p,
    input                                clk_n,
    input                                rst_in,

// DDR
    output                               mem_rst_n,
    output                               mem_ck,
    output                               mem_ck_n,
    output                               mem_cke,
    output                               mem_cs_n,
    output                               mem_ras_n,
    output                               mem_cas_n,
    output                               mem_we_n,
    output                               mem_odt,
    output      [MEM_ROW_ADDR_WIDTH-1:0] mem_a,
    output      [MEM_BADDR_WIDTH-1:0]    mem_ba,
    inout       [MEM_DQ_WIDTH/8-1:0]     mem_dqs,
    inout       [MEM_DQ_WIDTH/8-1:0]     mem_dqs_n,
    inout       [MEM_DQ_WIDTH-1:0]       mem_dq,
    output      [MEM_DQ_WIDTH/8-1:0]     mem_dm,
    output reg                           heart_beat_led,
    output                               ddr_init_done,
    output                               init_over_rx,

// MS72xx
    output                               rstn_out,
    output                               hd_scl,
    inout                                hd_sda,
    output                               hdmi_int_led,

// HDMI_in
    input                                pixclk_in,
    input                                vs_in,
    input                                hs_in,
    input                                de_in,
    input      [7:0]                     r_in,
    input      [7:0]                     g_in,
    input      [7:0]                     b_in,

// HDMI_out
    output                               pix_clk,
    output reg                           vs_out,
    output reg                           hs_out,
    output reg                           de_out,
    output reg    [7:0]                  r_out,
    output reg    [7:0]                  g_out,
    output reg    [7:0]                  b_out
);

/////////////////////////////////////////////////////////////////////////////////////
parameter CTRL_ADDR_WIDTH = MEM_ROW_ADDR_WIDTH + MEM_BADDR_WIDTH + MEM_COL_ADDR_WIDTH;
parameter TH_1S = 27'd33000000;

// MODE_1080p
parameter V_TOTAL   = 12'd1125;
parameter V_FP      = 12'd4;
parameter V_BP      = 12'd36;
parameter V_SYNC    = 12'd5;
parameter V_ACT     = 12'd1080;
parameter H_TOTAL   = 12'd2200;
parameter H_FP      = 12'd88;
parameter H_BP      = 12'd148;
parameter H_SYNC    = 12'd44;
parameter H_ACT     = 12'd1920;
parameter HV_OFFSET = 12'd0;
parameter X_WIDTH   = 12;
parameter Y_WIDTH   = 12;

/////////////////////////////////////////////////////////////////////////////////////
// 基本信号
reg  [15:0]                 rstn_1ms;
wire [15:0]                 o_rgb565;

wire                        cfg_clk;
wire                        locked;
wire                        init_over;
wire                        rx_init_done;
wire                        rx_rst_n;

wire                        core_clk;
wire                        pll_lock;
wire                        phy_pll_lock;
wire                        gpll_lock;
wire                        rst_gpll_lock;
wire                        ddrphy_cpd_lock;

wire                        de_o;
wire                        init_done;

wire                        hs_reg;
wire                        vs_reg;
wire                        rd_en;

wire [X_WIDTH-1:0]          act_x;
wire [Y_WIDTH-1:0]          act_y;

wire                        clk_125Mhz;
wire [15:0]                 hdmi_data_in;

// AXI bus
wire [CTRL_ADDR_WIDTH-1:0]  axi_awaddr;
wire                        axi_awuser_ap;
wire [3:0]                  axi_awuser_id;
wire [3:0]                  axi_awlen;
wire                        axi_awready;
wire                        axi_awvalid;
wire [MEM_DQ_WIDTH*8-1:0]   axi_wdata;
wire [MEM_DQ_WIDTH*8/8-1:0] axi_wstrb;
wire                        axi_wready;
wire [3:0]                  axi_wusero_id;
wire                        axi_wusero_last;
wire [CTRL_ADDR_WIDTH-1:0]  axi_araddr;
wire                        axi_aruser_ap;
wire [3:0]                  axi_aruser_id;
wire [3:0]                  axi_arlen;
wire                        axi_arready;
wire                        axi_arvalid;
wire [MEM_DQ_WIDTH*8-1:0]   axi_rdata;
wire                        axi_rvalid;
wire [3:0]                  axi_rid;
wire                        axi_rlast;

reg  [26:0]                 cnt;
reg                         rst_reg;

/////////////////////////////////////////////////////////////////////////////////////
// PLL
pll pll_gen_clk (
    .clkin1   (sys_clk),
    .clkout0  (pix_clk),
    .lock     (locked)
);

cfg_pll cfg_pll_inst (
    .clkout0  (cfg_clk),
    .lock     (),
    .clkin1   (sys_clk)
);

/////////////////////////////////////////////////////////////////////////////////////
// HDMI 初始化
ms72xx_ctl ms72xx_ctl(
    .clk         (cfg_clk),
    .rst_n       (rstn_out),
    .init_over_rx(rx_init_done),
    .init_over   (init_over),
    .iic_scl     (hd_scl),
    .iic_sda     (hd_sda)
);

assign init_over_rx = rx_init_done;
assign rx_rst_n     = rstn_out;
assign hdmi_int_led = init_over;

always @(posedge cfg_clk) begin
    if(!locked)
        rstn_1ms <= 16'd0;
    else begin
        if(rstn_1ms == 16'h2710)
            rstn_1ms <= rstn_1ms;
        else
            rstn_1ms <= rstn_1ms + 1'b1;
    end
end

assign rstn_out = (rstn_1ms == 16'h2710);

always @(posedge sys_clk) begin
    if(~rst_in)
        rst_reg <= 1'b1;
    else
        rst_reg <= 1'b0;
end

assign hdmi_data_in = {r_in[7:3], g_in[7:2], b_in[7:3]};

/////////////////////////////////////////////////////////////////////////////////////
// 灰度化
wire        y_vs;
wire        y_de;
wire        y_hs;
wire [7:0]  y_data;

RGB2YCbCr RGB2YCbCr_inst (
    .clk       (pixclk_in),
    .rst_n     (rstn_out),
    .vsync_in  (vs_in),
    .hsync_in  (hs_in),
    .de_in     (de_in),
    .red       (r_in),
    .green     (g_in),
    .blue      (b_in),
    .vsync_out (y_vs),
    .hsync_out (y_hs),
    .de_out    (y_de),
    .y         (y_data),
    .cb        (),
    .cr        ()
);

/////////////////////////////////////////////////////////////////////////////////////
// 第一次 3x3：给中值滤波用（直接复用官方 matrix_3x3）
wire [7:0]  med_matrix11;
wire [7:0]  med_matrix12;
wire [7:0]  med_matrix13;
wire [7:0]  med_matrix21;
wire [7:0]  med_matrix22;
wire [7:0]  med_matrix23;
wire [7:0]  med_matrix31;
wire [7:0]  med_matrix32;
wire [7:0]  med_matrix33;
wire        med_matrix_de;

matrix_3x3 #(
    .IMG_WIDTH  (11'd1920),
    .IMG_HEIGHT (11'd1080)
) u_matrix_3x3_for_median (
    .video_clk  (pixclk_in),
    .rst_n      (rstn_out),
    .video_vs   (y_vs),
    .video_de   (y_de),
    .video_data (y_data),

    .matrix_de  (med_matrix_de),
    .matrix11   (med_matrix11),
    .matrix12   (med_matrix12),
    .matrix13   (med_matrix13),
    .matrix21   (med_matrix21),
    .matrix22   (med_matrix22),
    .matrix23   (med_matrix23),
    .matrix31   (med_matrix31),
    .matrix32   (med_matrix32),
    .matrix33   (med_matrix33)
);

/////////////////////////////////////////////////////////////////////////////////////
// 中值滤波
wire        median_vs;
wire        median_hs;
wire        median_de;
wire [7:0]  median_y;

median_filter_3x3 u_median_filter_3x3 (
    .clk         (pixclk_in),
    .rst_n       (rstn_out),
    .vsync_in    (y_vs),
    .hsync_in    (med_matrix_de),
    .de_in       (med_matrix_de),

    .data11      (med_matrix11),
    .data12      (med_matrix12),
    .data13      (med_matrix13),
    .data21      (med_matrix21),
    .data22      (med_matrix22),
    .data23      (med_matrix23),
    .data31      (med_matrix31),
    .data32      (med_matrix32),
    .data33      (med_matrix33),

    .target_data (median_y),
    .vsync_out   (median_vs),
    .hsync_out   (median_hs),
    .de_out      (median_de)
);

/////////////////////////////////////////////////////////////////////////////////////
// 第二次 3x3：给局部二值化用（仍旧复用官方 matrix_3x3）
wire [7:0]  area_matrix11;
wire [7:0]  area_matrix12;
wire [7:0]  area_matrix13;
wire [7:0]  area_matrix21;
wire [7:0]  area_matrix22;
wire [7:0]  area_matrix23;
wire [7:0]  area_matrix31;
wire [7:0]  area_matrix32;
wire [7:0]  area_matrix33;
wire        area_matrix_de;

matrix_3x3 #(
    .IMG_WIDTH  (11'd1920),
    .IMG_HEIGHT (11'd1080)
) u_matrix_3x3_for_area_bin (
    .video_clk  (pixclk_in),
    .rst_n      (rstn_out),
    .video_vs   (median_vs),
    .video_de   (median_de),
    .video_data (median_y),

    .matrix_de  (area_matrix_de),
    .matrix11   (area_matrix11),
    .matrix12   (area_matrix12),
    .matrix13   (area_matrix13),
    .matrix21   (area_matrix21),
    .matrix22   (area_matrix22),
    .matrix23   (area_matrix23),
    .matrix31   (area_matrix31),
    .matrix32   (area_matrix32),
    .matrix33   (area_matrix33)
);

/////////////////////////////////////////////////////////////////////////////////////
// 局部二值化
wire        area_bin_vs;
wire        area_bin_de;
wire        area_bin_data;

area_bin u_area_bin(
    .video_clk     (pixclk_in),
    .rst_n         (rstn_out),

    .matrix_de     (area_matrix_de),
    .matrix_vs     (median_vs),
    .matrix11      (area_matrix11),
    .matrix12      (area_matrix12),
    .matrix13      (area_matrix13),
    .matrix21      (area_matrix21),
    .matrix22      (area_matrix22),
    .matrix23      (area_matrix23),
    .matrix31      (area_matrix31),
    .matrix32      (area_matrix32),
    .matrix33      (area_matrix33),

    .area_bin_vs   (area_bin_vs),
    .area_bin_de   (area_bin_de),
    .area_bin_data (area_bin_data)
);

/////////////////////////////////////////////////////////////////////////////////////
// 写入 DDR3 的数据显示：局部二值化结果
wire [15:0] write_data;
assign write_data = {16{area_bin_data}};

/////////////////////////////////////////////////////////////////////////////////////
// DDR3 帧缓存
fram_buf fram_buf(
    .ddr_clk        (core_clk),
    .ddr_rstn       (ddr_init_done),

    // data_in
    .vin_clk        (pixclk_in),
    .wr_fsync       (~area_bin_vs),
    .wr_en          (area_bin_de),
    .wr_data        (write_data),

    // data_out
    .vout_clk       (pix_clk),
    .rd_fsync       (vs_reg),
    .rd_en          (rd_en),
    .vout_de        (de_o),
    .vout_data      (o_rgb565),
    .init_done      (init_done),

    // axi bus
    .axi_awaddr     (axi_awaddr),
    .axi_awid       (axi_awuser_id),
    .axi_awlen      (axi_awlen),
    .axi_awsize     (),
    .axi_awburst    (),
    .axi_awready    (axi_awready),
    .axi_awvalid    (axi_awvalid),
    .axi_wdata      (axi_wdata),
    .axi_wstrb      (axi_wstrb),
    .axi_wlast      (axi_wusero_last),
    .axi_wvalid     (),
    .axi_wready     (axi_wready),
    .axi_bid        (4'd0),
    .axi_araddr     (axi_araddr),
    .axi_arid       (axi_aruser_id),
    .axi_arlen      (axi_arlen),
    .axi_arsize     (),
    .axi_arburst    (),
    .axi_arvalid    (axi_arvalid),
    .axi_arready    (axi_arready),
    .axi_rready     (),
    .axi_rdata      (axi_rdata),
    .axi_rvalid     (axi_rvalid),
    .axi_rlast      (axi_rlast),
    .axi_rid        (axi_rid)
);

/////////////////////////////////////////////////////////////////////////////////////
// HDMI 输出
always @(posedge pix_clk) begin
    vs_out <= vs_reg;
    hs_out <= hs_reg;
    de_out <= de_o;
    r_out  <= {o_rgb565[15:11], 3'd0};
    g_out  <= {o_rgb565[10:5],  2'd0};
    b_out  <= {o_rgb565[4:0],   3'd0};
end

/////////////////////////////////////////////////////////////////////////////////////
// 产生 VESA 时序
sync_vg #(
    .X_BITS   (X_WIDTH),
    .Y_BITS   (Y_WIDTH),
    .V_TOTAL  (V_TOTAL),
    .V_FP     (V_FP),
    .V_BP     (V_BP),
    .V_SYNC   (V_SYNC),
    .V_ACT    (V_ACT),
    .H_TOTAL  (H_TOTAL),
    .H_FP     (H_FP),
    .H_BP     (H_BP),
    .H_SYNC   (H_SYNC),
    .H_ACT    (H_ACT)
) sync_vg (
    .clk      (pix_clk),
    .rstn     (ddr_init_done),
    .vs_out   (vs_reg),
    .hs_out   (hs_reg),
    .de_out   (rd_en),
    .x_act    (act_x),
    .y_act    (act_y)
);

////////////////////////////////////////////////////////////////////////////////////////////
// DDR 参考时钟
GTP_INBUFGDS #(
    .IOSTANDARD("DEFAULT"),
    .TERM_DIFF("ON")
) u_gtp (
    .O  (clk_125Mhz),
    .I  (clk_p),
    .IB (clk_n)
);

////////////////////////////////////////////////////////////////////////////////////////////
// DDR3 控制器
ddr3_test u_ddr3_test_h (
    .ref_clk                   (clk_125Mhz),
    .resetn                    (rstn_out),
    .ddr_init_done             (ddr_init_done),

    .pll_lock                  (pll_lock),
    .core_clk                  (core_clk),

    .phy_pll_lock              (phy_pll_lock),
    .gpll_lock                 (gpll_lock),
    .rst_gpll_lock             (rst_gpll_lock),
    .ddrphy_cpd_lock           (ddrphy_cpd_lock),

    .axi_awaddr                (axi_awaddr),
    .axi_awuser_ap             (1'b0),
    .axi_awuser_id             (axi_awuser_id),
    .axi_awlen                 (axi_awlen),
    .axi_awready               (axi_awready),
    .axi_awvalid               (axi_awvalid),

    .axi_wdata                 (axi_wdata),
    .axi_wstrb                 (axi_wstrb),
    .axi_wready                (axi_wready),
    .axi_wusero_id             (),
    .axi_wusero_last           (axi_wusero_last),

    .axi_araddr                (axi_araddr),
    .axi_aruser_ap             (1'b0),
    .axi_aruser_id             (axi_aruser_id),
    .axi_arlen                 (axi_arlen),
    .axi_arready               (axi_arready),
    .axi_arvalid               (axi_arvalid),

    .axi_rdata                 (axi_rdata),
    .axi_rid                   (axi_rid),
    .axi_rlast                 (axi_rlast),
    .axi_rvalid                (axi_rvalid),

    .apb_clk                   (1'b0),
    .apb_rst_n                 (1'b1),
    .apb_sel                   (1'b0),
    .apb_enable                (1'b0),
    .apb_addr                  (8'b0),
    .apb_write                 (1'b0),
    .apb_ready                 (),
    .apb_wdata                 (16'b0),
    .apb_rdata                 (),

    .mem_rst_n                 (mem_rst_n),
    .mem_ck                    (mem_ck),
    .mem_ck_n                  (mem_ck_n),
    .mem_cke                   (mem_cke),
    .mem_cs_n                  (mem_cs_n),
    .mem_ras_n                 (mem_ras_n),
    .mem_cas_n                 (mem_cas_n),
    .mem_we_n                  (mem_we_n),
    .mem_odt                   (mem_odt),
    .mem_a                     (mem_a),
    .mem_ba                    (mem_ba),
    .mem_dqs                   (mem_dqs),
    .mem_dqs_n                 (mem_dqs_n),
    .mem_dq                    (mem_dq),
    .mem_dm                    (mem_dm),

    // debug
    .dbg_gate_start            (1'b0),
    .dbg_cpd_start             (1'b0),
    .dbg_ddrphy_rst_n          (1'b1),
    .dbg_gpll_scan_rst         (1'b0),
    .samp_position_dyn_adj     (1'b0),
    .init_samp_position_even   (32'd0),
    .init_samp_position_odd    (32'd0),
    .wrcal_position_dyn_adj    (1'b0),
    .init_wrcal_position       (32'd0),
    .force_read_clk_ctrl       (1'b0),
    .init_slip_step            (16'd0),
    .init_read_clk_ctrl        (12'd0),
    .debug_calib_ctrl          (),
    .dbg_slice_status          (),
    .dbg_slice_state           (),
    .debug_data                (),
    .dbg_dll_upd_state         (),
    .debug_gpll_dps_phase      (),
    .dbg_rst_dps_state         (),
    .dbg_tran_err_rst_cnt      (),
    .dbg_ddrphy_init_fail      (),
    .debug_cpd_offset_adj      (1'b0),
    .debug_cpd_offset_dir      (1'b0),
    .debug_cpd_offset          (10'd0),
    .debug_dps_cnt_dir0        (),
    .debug_dps_cnt_dir1        (),
    .ck_dly_en                 (1'b0),
    .init_ck_dly_step          (8'h0),
    .ck_dly_set_bin            (),
    .align_error               (),
    .debug_rst_state           (),
    .debug_cpd_state           ()
);

/////////////////////////////////////////////////////////////////////////////////////
// 心跳信号
always @(posedge core_clk) begin
    if (!ddr_init_done)
        cnt <= 27'd0;
    else if (cnt >= TH_1S)
        cnt <= 27'd0;
    else
        cnt <= cnt + 27'd1;
end

always @(posedge core_clk) begin
    if (!ddr_init_done)
        heart_beat_led <= 1'd1;
    else if (cnt >= TH_1S)
        heart_beat_led <= ~heart_beat_led;
end

endmodule
