`timescale 1ns / 1ps

module HDMI_IN_DDR3_ROI_top #(
    parameter MEM_ROW_ADDR_WIDTH   = 15,
    parameter MEM_COL_ADDR_WIDTH   = 10,
    parameter MEM_BADDR_WIDTH      = 3,
    parameter MEM_DQ_WIDTH         = 32,
    parameter MEM_DQS_WIDTH        = 32/8,

    parameter DEBUG_FORCE_BOX      = 0,
    parameter DEBUG_MODE           = 0,
    parameter BOX_THICK            = 8,
    parameter COLOR_MODE = 4,
// 0: blue only
// 1: green only
// 2: blue | green

    parameter FIX_BOX_X1           = 12'd500,
    parameter FIX_BOX_Y1           = 12'd300,
    parameter FIX_BOX_X2           = 12'd900,
    parameter FIX_BOX_Y2           = 12'd500
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

    // HDMI in
    input                                pixclk_in,
    input                                vs_in,
    input                                hs_in,
    input                                de_in,
    input      [7:0]                     r_in,
    input      [7:0]                     g_in,
    input      [7:0]                     b_in,

    // HDMI out
    output                               pix_clk,
    output reg                           vs_out,
    output reg                           hs_out,
    output reg                           de_out,
    output reg    [7:0]                  r_out,
    output reg    [7:0]                  g_out,
    output reg    [7:0]                  b_out
);

/////////////////////////////////////////////////////////////////////////////////////
// Parameters
parameter CTRL_ADDR_WIDTH = MEM_ROW_ADDR_WIDTH + MEM_BADDR_WIDTH + MEM_COL_ADDR_WIDTH;
parameter TH_1S           = 27'd33000000;

// 1080P
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

parameter X_BITS    = 12;
parameter Y_BITS    = 12;

/////////////////////////////////////////////////////////////////////////////////////
// Basic signals
reg  [15:0]                 rstn_1ms;

wire                        cfg_clk;
wire                        locked;
wire                        init_over;
wire                        rx_init_done;
wire                        rx_rst_n;
wire                        cfg_rst_n;
wire                        pixclk_in_rst_n;
wire                        pix_clk_rst_n;

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

wire [X_BITS-1:0]           act_x;
wire [Y_BITS-1:0]           act_y;

wire                        clk_125Mhz;

wire [15:0]                 hdmi_rgb565_in;
wire [15:0]                 o_rgb565;

reg  [26:0]                 cnt;
reg                         rst_reg;

// AXI bus
wire [CTRL_ADDR_WIDTH-1:0]  axi_awaddr;
wire [3:0]                  axi_awuser_id;
wire [3:0]                  axi_awlen;
wire                        axi_awready;
wire                        axi_awvalid;
wire [MEM_DQ_WIDTH*8-1:0]   axi_wdata;
wire [MEM_DQ_WIDTH*8/8-1:0] axi_wstrb;
wire                        axi_wready;
wire                        axi_wusero_last;
wire [CTRL_ADDR_WIDTH-1:0]  axi_araddr;
wire [3:0]                  axi_aruser_id;
wire [3:0]                  axi_arlen;
wire                        axi_arready;
wire                        axi_arvalid;
wire [MEM_DQ_WIDTH*8-1:0]   axi_rdata;
wire                        axi_rvalid;
wire [3:0]                  axi_rid;
wire                        axi_rlast;

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

reset_sync u_reset_sync_cfg (
    .clk         (cfg_clk),
    .async_rst_n (rstn_out),
    .sync_rst_n  (cfg_rst_n)
);

reset_sync u_reset_sync_pixclk_in (
    .clk         (pixclk_in),
    .async_rst_n (rstn_out),
    .sync_rst_n  (pixclk_in_rst_n)
);

reset_sync u_reset_sync_pix_clk (
    .clk         (pix_clk),
    .async_rst_n (rstn_out),
    .sync_rst_n  (pix_clk_rst_n)
);

/////////////////////////////////////////////////////////////////////////////////////
// HDMI init
ms72xx_ctl ms72xx_ctl(
    .clk         (cfg_clk),
    .rst_n       (cfg_rst_n),
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

assign hdmi_rgb565_in = {r_in[7:3], g_in[7:2], b_in[7:3]};

/////////////////////////////////////////////////////////////////////////////////////
// One-stage align before DDR write
reg        vs_in_d1;
reg        de_in_d1;
reg [15:0] rgb565_d1;

always @(posedge pixclk_in or negedge pixclk_in_rst_n) begin
    if(!pixclk_in_rst_n) begin
        vs_in_d1  <= 1'b0;
        de_in_d1  <= 1'b0;
        rgb565_d1 <= 16'd0;
    end
    else begin
        vs_in_d1  <= vs_in;
        de_in_d1  <= de_in;
        rgb565_d1 <= hdmi_rgb565_in;
    end
end

/////////////////////////////////////////////////////////////////////////////////////
// Preprocess chain
wire        y_vs;
wire        y_de;
wire        y_hs;
wire [7:0]  y_data;
wire [7:0]  cb_data;
wire [7:0]  cr_data;
wire        edge_vs;
wire        edge_de;
wire        edge_bin;
wire        edge_link_vs;
wire        edge_link_de;
wire        edge_link_bin;

localparam integer COLOR_ALIGN_MIN = 3;
localparam integer COLOR_ALIGN_MAX = 9;

wire        color_hit_raw;
wire        color_blue_hit;
wire        color_green_hit;
wire        color_yellow_hit;
wire        color_chroma_hit;
wire [8:0]  cb_ext;
wire [8:0]  cr_ext;
wire [8:0]  cb_delta;
wire [8:0]  cr_delta;
wire [8:0] chroma_sum;
wire       global_highlight_reject;
wire       global_bright_color_ok;
wire       anti_glare_ok_all;

wire       y_valid_for_green;

assign chroma_sum = cb_delta + cr_delta;

// 高亮/白反光全局拒绝：蓝、绿、黄都用
assign global_highlight_reject =
    (y_data >= 8'd238) ||
    ((y_data >= 8'd215) && (chroma_sum <= 9'd75));

assign global_bright_color_ok =
    (y_data < 8'd200) || (chroma_sum >= 9'd65);

assign anti_glare_ok_all =
    (!global_highlight_reject) && global_bright_color_ok;

// 绿色车牌亮度范围
assign y_valid_for_green = (y_data >= 8'd30) && (y_data <= 8'd235);
wire        score_color_in;
wire        score_bin_in;

reg         color_hit_edge;
reg [15:0]  color_hit_pipe;
reg [15:0]  color_de_pipe;

RGB2YCbCr RGB2YCbCr_inst (
    .clk       (pixclk_in),
    .rst_n     (pixclk_in_rst_n),
    .vsync_in  (vs_in),
    .hsync_in  (de_in),
    .de_in     (de_in),
    .red       (r_in[7:3]),
    .green     (g_in[7:2]),
    .blue      (b_in[7:3]),
    .vsync_out (y_vs),
    .hsync_out (y_hs),
    .de_out    (y_de),
    .y         (y_data),
    .cb        (cb_data),
    .cr        (cr_data)
);

assign cb_ext = {1'b0, cb_data};
assign cr_ext = {1'b0, cr_data};
assign cb_delta = (cb_ext >= 9'd128) ? (cb_ext - 9'd128) : (9'd128 - cb_ext);
assign cr_delta = (cr_ext >= 9'd128) ? (cr_ext - 9'd128) : (9'd128 - cr_ext);
wire y_valid_for_plate;
assign y_valid_for_plate = (y_data >= 8'd35) && (y_data <= 8'd225);

assign color_blue_hit =
    anti_glare_ok_all &&
    y_valid_for_plate &&
    (cb_ext >= 9'd145) && (cb_ext <= 9'd245) &&
    (cr_ext >= 9'd55)  && (cr_ext <= 9'd155) &&
    (cb_ext >= (cr_ext + 9'd25));
 // 横向连续蓝色过滤：过滤零散蓝色反�?小蓝�?
reg [5:0] blue_run_cnt;
reg       color_blue_run_hit;
reg [5:0] blue_run_cnt_next;

wire selected_color_hit;

assign selected_color_hit =
    (COLOR_MODE == 0) ? color_blue_run_hit :
    (COLOR_MODE == 1) ? color_green_run_hit :
    (COLOR_MODE == 2) ? (color_blue_run_hit | color_green_run_hit) :
    (COLOR_MODE == 3) ? color_yellow_run_hit :
    (COLOR_MODE == 4) ? (color_blue_run_hit | color_green_run_hit | color_yellow_run_hit) :
                        color_blue_run_hit;

assign color_hit_raw = y_de && selected_color_hit;



always @(*) begin
    if(!y_de)
        blue_run_cnt_next = 6'd0;
    else if(color_blue_hit) begin
        if(blue_run_cnt < 6'd63)
            blue_run_cnt_next = blue_run_cnt + 1'b1;
        else
            blue_run_cnt_next = blue_run_cnt;
    end
    else
        blue_run_cnt_next = 6'd0;
end

always @(posedge pixclk_in or negedge pixclk_in_rst_n) begin
    if(!pixclk_in_rst_n) begin
        blue_run_cnt       <= 6'd0;
        color_blue_run_hit <= 1'b0;
    end
    else begin
        blue_run_cnt       <= blue_run_cnt_next;
        color_blue_run_hit <= y_de && color_blue_hit && (blue_run_cnt_next >= 6'd8);
    end
end



assign color_green_hit =
    anti_glare_ok_all &&
    y_valid_for_green &&
    (cb_ext >= 9'd62)  && (cb_ext <= 9'd155) &&
    (cr_ext >= 9'd28)  && (cr_ext <= 9'd135) &&
    (cb_ext >= (cr_ext + 9'd2)) &&
    (chroma_sum >= 9'd38);
    // 横向连续绿色过滤：过滤零散绿色反�?背景�?
reg [5:0] green_run_cnt;
reg       color_green_run_hit;
reg [5:0] green_run_cnt_next;

always @(*) begin
    if(!y_de)
        green_run_cnt_next = 6'd0;
    else if(color_green_hit) begin
        if(green_run_cnt < 6'd63)
            green_run_cnt_next = green_run_cnt + 1'b1;
        else
            green_run_cnt_next = green_run_cnt;
    end
    else
        green_run_cnt_next = 6'd0;
end

always @(posedge pixclk_in or negedge pixclk_in_rst_n) begin
    if(!pixclk_in_rst_n) begin
        green_run_cnt       <= 6'd0;
        color_green_run_hit <= 1'b0;
    end
    else begin
        green_run_cnt       <= green_run_cnt_next;
        color_green_run_hit <= y_de && color_green_hit && (green_run_cnt_next >= 6'd8);
    end
end
reg [5:0] yellow_run_cnt;
reg       color_yellow_run_hit;
reg [5:0] yellow_run_cnt_next;

wire y_valid_for_yellow;

assign y_valid_for_yellow = (y_data >= 8'd45) && (y_data <= 8'd230);

assign color_yellow_hit =
    anti_glare_ok_all &&
    y_valid_for_yellow &&
    (cb_ext >= 9'd12)  && (cb_ext <= 9'd125) &&
    (cr_ext >= 9'd135) && (cr_ext <= 9'd245) &&
    (cr_ext >= (cb_ext + 9'd45)) &&
    (chroma_sum >= 9'd60);

    // 横向连续黄色过滤：过滤零散黄色反�?灯光/背景�?
always @(*) begin
    if(!y_de)
        yellow_run_cnt_next = 6'd0;
    else if(color_yellow_hit) begin
        if(yellow_run_cnt < 6'd63)
            yellow_run_cnt_next = yellow_run_cnt + 1'b1;
        else
            yellow_run_cnt_next = yellow_run_cnt;
    end
    else
        yellow_run_cnt_next = 6'd0;
end

always @(posedge pixclk_in or negedge pixclk_in_rst_n) begin
    if(!pixclk_in_rst_n) begin
        yellow_run_cnt       <= 6'd0;
        color_yellow_run_hit <= 1'b0;
    end
    else begin
        yellow_run_cnt       <= yellow_run_cnt_next;
        color_yellow_run_hit <= y_de && color_yellow_hit && (yellow_run_cnt_next >= 6'd10);
    end
end

assign color_chroma_hit =
    (y_data >= 8'd18) &&
    ((cb_delta + cr_delta) >= 9'd42) &&
    (cb_delta >= 9'd10 || cr_delta >= 9'd10);

                                


wire [15:0] gray565_in;
reg         y_vs_d1;
reg         y_de_d1;
reg [15:0]  gray565_d1;

assign gray565_in = {y_data[7:3], y_data[7:2], y_data[7:3]};

always @(posedge pixclk_in or negedge pixclk_in_rst_n) begin
    if(!pixclk_in_rst_n) begin
        y_vs_d1    <= 1'b0;
        y_de_d1    <= 1'b0;
        gray565_d1 <= 16'd0;
    end
    else begin
        y_vs_d1    <= y_vs;
        y_de_d1    <= y_de;
        gray565_d1 <= gray565_in;
    end
end

always @(posedge pixclk_in or negedge pixclk_in_rst_n) begin
    if(!pixclk_in_rst_n) begin
        color_hit_pipe <= 16'd0;
        color_de_pipe  <= 16'd0;
        color_hit_edge <= 1'b0;
    end
    else begin
        color_hit_pipe <= {color_hit_pipe[14:0], color_hit_raw};
        color_de_pipe  <= {color_de_pipe[14:0], y_de};

        if(|color_de_pipe[COLOR_ALIGN_MAX:COLOR_ALIGN_MIN])
            color_hit_edge <= |(color_hit_pipe[COLOR_ALIGN_MAX:COLOR_ALIGN_MIN] &
                                color_de_pipe[COLOR_ALIGN_MAX:COLOR_ALIGN_MIN]);
        else
            color_hit_edge <= 1'b0;
    end
end

Plate_Edge_SobelX #(
    .IMG_WIDTH  (1920),
    .IMG_HEIGHT (1080),
    .EDGE_TH    (90),
    .WEAK_EDGE_TH(58),
    .DARK_Y_TH  (110)
) u_Plate_Edge_SobelX (
    .clk          (pixclk_in),
    .rst_n        (pixclk_in_rst_n),
    .vs_in        (y_vs),
    .de_in        (y_de),
    .y_in         (y_data),
    .vs_out       (edge_vs),
    .de_out       (edge_de),
    .edge_bin_out (edge_bin)
);

Plate_Edge_Link #(
    .LINK_LEN (6)
) u_Plate_Edge_Link (
    .clk          (pixclk_in),
    .rst_n        (pixclk_in_rst_n),
    .vs_in        (edge_vs),
    .de_in        (edge_de),
    .edge_bin_in  (edge_bin),
    .vs_out       (edge_link_vs),
    .de_out       (edge_link_de),
    .edge_bin_out (edge_link_bin)
);

wire strong_color_hit;
wire weak_color_hit;
wire selected_color_hit_aligned;

assign strong_color_hit           = color_hit_edge;
assign weak_color_hit             = color_hit_edge;
assign selected_color_hit_aligned = strong_color_hit;

assign score_color_in = selected_color_hit_aligned;
assign score_bin_in   = edge_link_bin;

wire                  run_valid_w       /* synthesis PAP_MARK_DEBUG="true" */;
wire [X_BITS-1:0]     run_x1_w          /* synthesis PAP_MARK_DEBUG="true" */;
wire [X_BITS-1:0]     run_x2_w          /* synthesis PAP_MARK_DEBUG="true" */;
wire [Y_BITS-1:0]     run_y_w           /* synthesis PAP_MARK_DEBUG="true" */;
wire [X_BITS-1:0]     run_width_w       /* synthesis PAP_MARK_DEBUG="true" */;
wire [15:0]           run_color_count_w /* synthesis PAP_MARK_DEBUG="true" */;
wire [15:0]           run_edge_count_w  /* synthesis PAP_MARK_DEBUG="true" */;
wire                  run_frame_done_w  /* synthesis PAP_MARK_DEBUG="true" */;

run_segment_detect #(
    .IMG_WIDTH   (1920),
    .IMG_HEIGHT  (1080),
    .X_BITS      (X_BITS),
    .Y_BITS      (Y_BITS),
    .RUN_MIN_LEN (12)
) u_run_segment_detect (
    .clk             (pixclk_in),
    .rst_n           (pixclk_in_rst_n),
    .bin_vsync       (edge_link_vs),
    .bin_de          (edge_link_de),
    .color_hit_in    (selected_color_hit_aligned),
    .edge_hit_in     (edge_link_bin),
    .run_valid       (run_valid_w),
    .run_x1          (run_x1_w),
    .run_x2          (run_x2_w),
    .run_y           (run_y_w),
    .run_width       (run_width_w),
    .run_color_count (run_color_count_w),
    .run_edge_count  (run_edge_count_w),
    .frame_done      (run_frame_done_w)
);

/////////////////////////////////////////////////////////////////////////////////////
// ROI raw
wire                  roi_valid_raw;
wire [X_BITS-1:0]     roi_x1_raw;
wire [Y_BITS-1:0]     roi_y1_raw;
wire [X_BITS-1:0]     roi_x2_raw;
wire [Y_BITS-1:0]     roi_y2_raw;
wire [X_BITS-1:0]     roi_w_raw;
wire [Y_BITS-1:0]     roi_h_raw;
wire [31:0]           roi_area_raw;
wire                  roi_frame_done_raw;

Plate_Window_Scorer #(
    .IMG_WIDTH            (1920),
    .IMG_HEIGHT           (1080),
    .X_BITS               (X_BITS),
    .Y_BITS               (Y_BITS),
    .SEARCH_LEFT          (16),
    .SEARCH_RIGHT         (16),
    .SEARCH_TOP           (8),
    .SEARCH_BOTTOM        (8),
    .WIN_W                (32),
    .ROW_SCORE_TH         (40),
    .COLOR_MIN_SUM        (6),
    .EDGE_MIN_SUM         (8),
    .EDGE_MAX_SUM         (24),
    .X_TOL                (48),
    .MIN_BAND_ROWS        (8),
    .MAX_BAND_ROWS        (20),
    .ROI_W                (224),
    .ROI_H                (80),
    .COLOR_WEIGHT         (20),
    .PEAK_BIN_TH          (2),
    .PEAK_MIN             (3),
    .PEAK_MAX             (7),
    .COLOR_RATIO_NUM      (2),
    .COLOR_RATIO_DEN      (1),
    .BAND_MIN_STRONG_ROWS (5),
    .BAND_MAX_X_SPAN      (64),
    .BAND_MIN_AVG_SCORE   (56),
    .SMOOTH_SHIFT         (4),
    .MISS_HOLD_FRAMES     (20),
    .LOCK_X_RADIUS        (360),
    .LOCK_Y_RADIUS        (180),
    .SWITCH_MARGIN        (380),
    .SWITCH_X_RADIUS      (160),
    .SWITCH_Y_RADIUS      (96),
    .LOST_CONFIRM_FRAMES  (20),
    .SEARCH_EDGE_MIN      (4),
    .SEARCH_COLOR_MIN     (1),
    .SEARCH_LOOSE_EDGE_MIN(2),
    .SEARCH_LOOSE_COLOR_MIN(1),
    .TRACK_EDGE_MIN       (2),
    .TRACK_COLOR_MIN      (1),
    .TRACK_LOOSE_EDGE_MIN (1),
    .TRACK_LOOSE_COLOR_MIN(1),
    .TRACK_PAD_X          (200),
    .TRACK_PAD_Y          (90),
    .FAR_CONFIRM_FRAMES   (12),
    .FORCE_SWITCH_LOST_FRAMES(20),
    .COLOR_SWITCH_MARGIN_STRONG(6),
    .EDGE_COLOR_PAD       (8)
) u_Plate_Window_Scorer (
    .clk            (pixclk_in),
    .rst_n          (pixclk_in_rst_n),
    .bin_vsync    (edge_link_vs),
    .bin_de       (edge_link_de),
    .bin_data     (edge_link_bin),
    .color_hit_in (color_hit_edge),
    .roi_valid      (roi_valid_raw),
    .roi_x1         (roi_x1_raw),
    .roi_y1         (roi_y1_raw),
    .roi_x2         (roi_x2_raw),
    .roi_y2         (roi_y2_raw),
    .roi_w          (roi_w_raw),
    .roi_h          (roi_h_raw),
    .roi_area       (roi_area_raw),
    .roi_frame_done (roi_frame_done_raw)
);

wire              roi_valid_adj;
wire [X_BITS-1:0] roi_x1_adj;
wire [Y_BITS-1:0] roi_y1_adj;
wire [X_BITS-1:0] roi_x2_adj;
wire [Y_BITS-1:0] roi_y2_adj;

ROI_Box_Adjust #(
    .IMG_WIDTH   (1920),
    .IMG_HEIGHT  (1080),
    .X_BITS      (X_BITS),
    .Y_BITS      (Y_BITS),
    .PAD_X       (8),
    .PAD_Y       (4)
) u_ROI_Box_Adjust (
    .clk          (pixclk_in),
    .rst_n        (pixclk_in_rst_n),
    .roi_valid_in (roi_valid_raw),
    .roi_x1_in    (roi_x1_raw),
    .roi_y1_in    (roi_y1_raw),
    .roi_x2_in    (roi_x2_raw),
    .roi_y2_in    (roi_y2_raw),
    .roi_valid_out(roi_valid_adj),
    .roi_x1_out   (roi_x1_adj),
    .roi_y1_out   (roi_y1_adj),
    .roi_x2_out   (roi_x2_adj),
    .roi_y2_out   (roi_y2_adj)
);

wire              roi_valid_map;
wire [X_BITS-1:0] roi_x1_map;
wire [Y_BITS-1:0] roi_y1_map;
wire [X_BITS-1:0] roi_x2_map;
wire [Y_BITS-1:0] roi_y2_map;

reg roi_frame_done_adj;

always @(posedge pixclk_in or negedge pixclk_in_rst_n) begin
    if(!pixclk_in_rst_n)
        roi_frame_done_adj <= 1'b0;
    else
        roi_frame_done_adj <= roi_frame_done_raw;
end

assign roi_valid_map = roi_valid_adj;
assign roi_x1_map    = roi_x1_adj;
assign roi_y1_map    = roi_y1_adj;
assign roi_x2_map    = roi_x2_adj;
assign roi_y2_map    = roi_y2_adj;

/////////////////////////////////////////////////////////////////////////////////////
// ROI cropper
wire              roi_frame_start_w;
wire              roi_de_w;
wire [7:0]        roi_r_w;
wire [7:0]        roi_g_w;
wire [7:0]        roi_b_w;
wire [X_BITS-1:0] roi_rel_x_w;
wire [Y_BITS-1:0] roi_rel_y_w;

ROI_Cropper_Simple #(
    .IMG_WIDTH    (1920),
    .IMG_HEIGHT   (1080),
    .X_BITS       (X_BITS),
    .Y_BITS       (Y_BITS)
) u_ROI_Cropper_Simple (
    .clk             (pixclk_in),
    .rst_n           (pixclk_in_rst_n),
    .src_vsync       (vs_in),
    .src_de          (de_in),
    .src_r           (r_in),
    .src_g           (g_in),
    .src_b           (b_in),
    .roi_valid_in    (roi_valid_map),
    .roi_x1_in       (roi_x1_map),
    .roi_y1_in       (roi_y1_map),
    .roi_x2_in       (roi_x2_map),
    .roi_y2_in       (roi_y2_map),
    .roi_frame_start (roi_frame_start_w),
    .roi_de          (roi_de_w),
    .roi_r           (roi_r_w),
    .roi_g           (roi_g_w),
    .roi_b           (roi_b_w),
    .roi_rel_x       (roi_rel_x_w),
    .roi_rel_y       (roi_rel_y_w)
);

/////////////////////////////////////////////////////////////////////////////////////
// ROI coords cross clock domain: pixclk_in -> pix_clk
reg roi_map_done_d0, roi_map_done_d1, roi_map_done_d2;
reg roi_valid_hold_in;
reg [X_BITS-1:0] roi_x1_hold_in, roi_x2_hold_in;
reg [Y_BITS-1:0] roi_y1_hold_in, roi_y2_hold_in;
reg [6:0] roi_miss_hold_in;
reg roi_update_toggle_in;

always @(posedge pixclk_in or negedge pixclk_in_rst_n) begin
    if(!pixclk_in_rst_n) begin
        roi_map_done_d0      <= 1'b0;
        roi_map_done_d1      <= 1'b0;
        roi_map_done_d2      <= 1'b0;
        roi_valid_hold_in    <= 1'b0;
        roi_x1_hold_in       <= {X_BITS{1'b0}};
        roi_x2_hold_in       <= {X_BITS{1'b0}};
        roi_y1_hold_in       <= {Y_BITS{1'b0}};
        roi_y2_hold_in       <= {Y_BITS{1'b0}};
        roi_miss_hold_in     <= 7'd0;
        roi_update_toggle_in <= 1'b0;
    end
    else begin
        roi_map_done_d0 <= roi_frame_done_adj;
        roi_map_done_d1 <= roi_map_done_d0;
        roi_map_done_d2 <= roi_map_done_d1;

        if(roi_map_done_d2) begin
            if(roi_valid_map) begin
                roi_valid_hold_in <= 1'b1;
                roi_x1_hold_in    <= roi_x1_map;
                roi_x2_hold_in    <= roi_x2_map;
                roi_y1_hold_in    <= roi_y1_map;
                roi_y2_hold_in    <= roi_y2_map;
                roi_miss_hold_in  <= 7'd0;
            end
            else if(roi_valid_hold_in && (roi_miss_hold_in < 7'd20)) begin
                roi_miss_hold_in <= roi_miss_hold_in + 1'b1;
            end
            else begin
                roi_valid_hold_in <= 1'b0;
                roi_miss_hold_in  <= 7'd0;
            end

            roi_update_toggle_in <= ~roi_update_toggle_in;
        end
    end
end

reg roi_update_meta0, roi_update_meta1, roi_update_meta2;
reg roi_update_meta2_d;

reg              roi_valid_disp;
reg [X_BITS-1:0] roi_x1_disp, roi_x2_disp;
reg [Y_BITS-1:0] roi_y1_disp, roi_y2_disp;

always @(posedge pix_clk or negedge pix_clk_rst_n) begin
    if(!pix_clk_rst_n) begin
        roi_update_meta0   <= 1'b0;
        roi_update_meta1   <= 1'b0;
        roi_update_meta2   <= 1'b0;
        roi_update_meta2_d <= 1'b0;

        roi_valid_disp <= 1'b0;
        roi_x1_disp    <= {X_BITS{1'b0}};
        roi_x2_disp    <= {X_BITS{1'b0}};
        roi_y1_disp    <= {Y_BITS{1'b0}};
        roi_y2_disp    <= {Y_BITS{1'b0}};
    end
    else begin
        roi_update_meta0   <= roi_update_toggle_in;
        roi_update_meta1   <= roi_update_meta0;
        roi_update_meta2   <= roi_update_meta1;
        roi_update_meta2_d <= roi_update_meta2;

        if(roi_update_meta2 ^ roi_update_meta2_d) begin
            roi_valid_disp <= roi_valid_hold_in;
            roi_x1_disp    <= roi_x1_hold_in;
            roi_x2_disp    <= roi_x2_hold_in;
            roi_y1_disp    <= roi_y1_hold_in;
            roi_y2_disp    <= roi_y2_hold_in;
        end
    end
end

/////////////////////////////////////////////////////////////////////////////////////
// DDR frame buffer
// DEBUG_MODE:
// 0 - normal ROI display
// 1 - write color mask to frame buffer
// 2 - write edge mask to frame buffer
wire        debug_color_mode;
wire        debug_edge_mode;
wire        debug_mask_mode;
wire [15:0] debug_color_data;
wire [15:0] debug_edge_data;
wire [15:0] write_data;
wire        write_fsync;
wire        write_en;

assign debug_color_mode = (DEBUG_MODE == 1);
assign debug_edge_mode  = (DEBUG_MODE == 2);
assign debug_mask_mode  = debug_color_mode | debug_edge_mode;

assign debug_color_data = color_hit_raw ? 16'h001F : 16'h0000;  // blue
assign debug_edge_data  = edge_link_bin ? 16'hFFFF : 16'h0000;  // white

assign write_data  = debug_color_mode ? debug_color_data :
                     debug_edge_mode  ? debug_edge_data  :
                                        rgb565_d1;
assign write_fsync = debug_color_mode ? ~y_vs :
                     debug_edge_mode  ? ~edge_link_vs :
                                        ~vs_in_d1;
assign write_en    = debug_color_mode ? y_de :
                     debug_edge_mode  ? edge_link_de :
                                        de_in_d1;

fram_buf fram_buf(
    .ddr_clk        (core_clk),
    .ddr_rstn       (ddr_init_done),
    .vin_clk        (pixclk_in),
    .wr_fsync       (write_fsync),
    .wr_en          (write_en),
    .wr_data        (write_data),
    .vout_clk       (pix_clk),
    .rd_fsync       (vs_reg),
    .rd_en          (rd_en),
    .vout_de        (de_o),
    .vout_data      (o_rgb565),
    .init_done      (init_done),
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
// Display timing
sync_vg #(
    .X_BITS   (X_BITS),
    .Y_BITS   (Y_BITS),
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

/////////////////////////////////////////////////////////////////////////////////////
// Choose debug box source
wire              sel_roi_valid;
wire [X_BITS-1:0] sel_roi_x1;
wire [X_BITS-1:0] sel_roi_x2;
wire [Y_BITS-1:0] sel_roi_y1;
wire [Y_BITS-1:0] sel_roi_y2;

assign sel_roi_valid = (DEBUG_FORCE_BOX != 0) ? 1'b1       : roi_valid_disp;
assign sel_roi_x1    = (DEBUG_FORCE_BOX != 0) ? FIX_BOX_X1 : roi_x1_disp;
assign sel_roi_y1    = (DEBUG_FORCE_BOX != 0) ? FIX_BOX_Y1 : roi_y1_disp;
assign sel_roi_x2    = (DEBUG_FORCE_BOX != 0) ? FIX_BOX_X2 : roi_x2_disp;
assign sel_roi_y2    = (DEBUG_FORCE_BOX != 0) ? FIX_BOX_Y2 : roi_y2_disp;

/////////////////////////////////////////////////////////////////////////////////////
// Overlay coarse green box
wire on_box_top;
wire on_box_bottom;
wire on_box_left;
wire on_box_right;
wire on_roi_box;

assign on_box_top =
    sel_roi_valid &&
    (act_x >= sel_roi_x1) && (act_x <= sel_roi_x2) &&
    (act_y >= sel_roi_y1) && (act_y < sel_roi_y1 + BOX_THICK);

assign on_box_bottom =
    sel_roi_valid &&
    (act_x >= sel_roi_x1) && (act_x <= sel_roi_x2) &&
    (act_y <= sel_roi_y2) && (act_y > sel_roi_y2 - BOX_THICK);

assign on_box_left =
    sel_roi_valid &&
    (act_y >= sel_roi_y1) && (act_y <= sel_roi_y2) &&
    (act_x >= sel_roi_x1) && (act_x < sel_roi_x1 + BOX_THICK);

assign on_box_right =
    sel_roi_valid &&
    (act_y >= sel_roi_y1) && (act_y <= sel_roi_y2) &&
    (act_x <= sel_roi_x2) && (act_x > sel_roi_x2 - BOX_THICK);

assign on_roi_box = on_box_top | on_box_bottom | on_box_left | on_box_right;
wire inside_roi_disp;

assign inside_roi_disp =
    sel_roi_valid &&
    (act_x >= sel_roi_x1) && (act_x <= sel_roi_x2) &&
    (act_y >= sel_roi_y1) && (act_y <= sel_roi_y2);

/////////////////////////////////////////////////////////////////////////////////////
// HDMI output: original image + green ROI box
/////////////////////////////////////////////////////////////////////////////////////
// HDMI output: ROI inside image, outside black, no green box
/////////////////////////////////////////////////////////////////////////////////////
// HDMI output: ROI inside image, outside black, with green ROI box
always @(posedge pix_clk or negedge pix_clk_rst_n) begin
    if(!pix_clk_rst_n) begin
        vs_out <= 1'b0;
        hs_out <= 1'b0;
        de_out <= 1'b0;
        r_out  <= 8'd0;
        g_out  <= 8'd0;
        b_out  <= 8'd0;
    end
    else begin
        vs_out <= vs_reg;
        hs_out <= hs_reg;
        de_out <= de_o;

        if(!de_o) begin
            r_out <= 8'd0;
            g_out <= 8'd0;
            b_out <= 8'd0;
        end
        else if(debug_mask_mode) begin
            r_out <= {o_rgb565[15:11], 3'd0};
            g_out <= {o_rgb565[10:5],  2'd0};
            b_out <= {o_rgb565[4:0],   3'd0};
        end
        else if(on_roi_box) begin
            // Show green ROI box
            r_out <= 8'd0;
            g_out <= 8'hFF;
            b_out <= 8'd0;
        end
        else if(inside_roi_disp) begin
            // ROI 内部输出原始 RGB 图像
            r_out <= {o_rgb565[15:11], 3'd0};
            g_out <= {o_rgb565[10:5],  2'd0};
            b_out <= {o_rgb565[4:0],   3'd0};
        end
        else begin
            // ROI 外部全部置黑
            r_out <= 8'd0;
            g_out <= 8'd0;
            b_out <= 8'd0;
        end
    end
end

GTP_INBUFGDS #(
    .IOSTANDARD("DEFAULT"),
    .TERM_DIFF("ON")
) u_gtp (
    .O  (clk_125Mhz),
    .I  (clk_p),
    .IB (clk_n)
);
////////////////////////////////////////////////////////////////////////////////////////////
// DDR3 controller
ddr3_test u_ddr3_test_h (
    ////////////////////////////////////////////////////////////////////////////////////////////
// DDR reference clock

////////////////////////////////////////////////////////////////////////////////////////////
// DDR3 controller
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
// Heartbeat LED
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
