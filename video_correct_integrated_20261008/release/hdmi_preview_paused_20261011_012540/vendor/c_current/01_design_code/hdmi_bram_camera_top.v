`timescale 1ns/1ps
// Local camera diagnostic: 320x180 RGB888 buffers, scaled to 1080p output.
// BRAM only; this does not implement the final DDR frame buffer.
module hdmi_bram_camera_top #(parameter [11:0] OUTPUT_H_FRONT=12'd88, parameter DEBUG_OVERLAY=1)(
 input sys_clk_27m,rst_n,hd_rx_pclk,hd_rx_vs,hd_rx_hs,hd_rx_de,
 input [23:0] hd_rx_data,
 output hd_tx_pclk,hd_tx_vs,hd_tx_hs,hd_tx_de,
 output [23:0] hd_tx_data,
 output hd_reset_n,hd_scl,hdmi_init_done,rx_init_done,inout hd_sda);
wire cfg_clk,pix_clk,cfg_locked,pix_locked;
config_pll_27m_10m cp(.clkin1(sys_clk_27m),.clkout0(cfg_clk),.lock(cfg_locked));
video_pll_27m_148m5 vp(.clkin1(sys_clk_27m),.clkout0(pix_clk),.lock(pix_locked));
reg [15:0] reset_count;
always @(posedge cfg_clk or negedge rst_n)begin
 if(!rst_n)reset_count<=0;
 else if(!cfg_locked)reset_count<=0;
 else if(reset_count<10000)reset_count<=reset_count+1'b1;
end
assign hd_reset_n=rst_n && cfg_locked && reset_count==10000;
reg [1:0] rx_reset_pipe,video_reset_pipe;
always @(posedge hd_rx_pclk or negedge hd_reset_n)begin
 if(!hd_reset_n)rx_reset_pipe<=0;else rx_reset_pipe<={rx_reset_pipe[0],1'b1};
end
wire video_reset_async=rst_n && pix_locked;
always @(posedge pix_clk or negedge video_reset_async)begin
 if(!video_reset_async)video_reset_pipe<=0;else video_reset_pipe<={video_reset_pipe[0],1'b1};
end
wire video_reset_n=video_reset_pipe[1];
// Capture the source-synchronous interface before DE drives BRAM write logic.
// Data and DE share this one-cycle latency; never delay only the qualifier.
reg rx_de_q;
reg [23:0] rx_pixel_q;
always @(posedge hd_rx_pclk or negedge rx_reset_pipe[1])begin
 if(!rx_reset_pipe[1])begin rx_de_q<=0;rx_pixel_q<=0;end
 else begin rx_de_q<=hd_rx_de;rx_pixel_q<=hd_rx_data;end
end
wire [31:0] rx_status;
wire [15:0] rx_status_reads;
wire [7:0] rx_pixel_config;
wire rx_pixel_config_valid;
ms72xx_shared_config #(.TX_FIRST(1)) config_bus(.cfg_clk(cfg_clk),.reset_n(hd_reset_n),.rx_done(rx_init_done),.tx_done(hdmi_init_done),.rx_status(rx_status),.rx_status_reads(rx_status_reads),.rx_pixel_config(rx_pixel_config),.rx_pixel_config_valid(rx_pixel_config_valid),.scl(hd_scl),.sda(hd_sda));
wire [11:0] hc,vc;
wire vs,hs,de;
// At 148.5 MHz, front porch 528 selects 50 Hz; 88 selects 60 Hz.
video_timing_vtc #(.H_FRONT(OUTPUT_H_FRONT)) vtc(.clk(pix_clk),.rst_n(video_reset_n),.h_cnt(hc),.v_cnt(vc),.hsync(hs),.vsync(vs),.de(de));
wire [11:0] x=hc-192,y=vc-41;
reg [8:0] scaled_x;
reg [7:0] scaled_y;
reg [15:0] read_address;
always @(posedge pix_clk or negedge video_reset_n)begin
 if(!video_reset_n)begin scaled_x<=0;scaled_y<=0;read_address<=0;end
 else begin
  scaled_x<=de ? x/6 : 0;scaled_y<=de ? y/6 : 0;
  read_address<=scaled_y*320+scaled_x;
 end
end
reg [2:0] hs_pipe,vs_pipe,de_pipe;
reg [2:0] overlay_pipe;
reg [23:0] fallback_0,fallback_1,fallback_2;
reg previous_vs;
always @(posedge pix_clk or negedge video_reset_n)begin
 if(!video_reset_n)previous_vs<=0;else previous_vs<=vs;
end
wire [23:0] stored_pixel;
wire frame_valid;wire [15:0] samples_written;wire [2:0] writer_flags;
hdmi_bram_probe camera_store(.wr_clk(hd_rx_pclk),.wr_reset_n(rx_reset_pipe[1]),.de(rx_de_q),.pixel(rx_pixel_q),.rd_clk(pix_clk),.rd_reset_n(video_reset_n),.frame_start(vs && !previous_vs),.rd_enable(de_pipe[1]),.rd_addr(de_pipe[1] ? read_address : 16'd0),.rd_pixel(stored_pixel),.frame_valid(frame_valid),.samples_written(samples_written),.writer_flags(writer_flags));
reg clock_seen,de_seen;
always @(posedge hd_rx_pclk or negedge rx_reset_pipe[1])begin
 if(!rx_reset_pipe[1])begin clock_seen<=0;de_seen<=0;end
 else begin clock_seen<=1;if(rx_de_q)de_seen<=1;end
end
reg [2:0] flags_meta,flags_sync;
always @(posedge pix_clk or negedge video_reset_n)begin
 if(!video_reset_n)begin flags_meta<=0;flags_sync<=0;end
 else begin flags_meta<={rx_init_done,clock_seen,de_seen};flags_sync<=flags_meta;end
end
wire [18:0] buffer_debug;
wire [56:0] config_debug;
wire ignored_valid_0,ignored_busy_0,ignored_valid_1,ignored_busy_1;
cdc_snapshot #(.WIDTH(19)) debug_buffer(.src_clk(hd_rx_pclk),.src_reset_n(rx_reset_pipe[1]),.src_data({writer_flags,samples_written}),.dst_clk(pix_clk),.dst_reset_n(video_reset_n),.request(vs && !previous_vs),.dst_data(buffer_debug),.valid(ignored_valid_0),.busy(ignored_busy_0));
cdc_snapshot #(.WIDTH(57)) debug_config(.src_clk(cfg_clk),.src_reset_n(hd_reset_n),.src_data({rx_pixel_config_valid,rx_pixel_config,rx_status_reads,rx_status}),.dst_clk(pix_clk),.dst_reset_n(video_reset_n),.request(vs && !previous_vs),.dst_data(config_debug),.valid(ignored_valid_1),.busy(ignored_busy_1));
// Six rows: capture count, flags, RX counters, read count, valid/PCLK register.
wire [15:0] debug_word=(y<780) ? buffer_debug[15:0] :
 (y<840) ? {10'd0,flags_sync,buffer_debug[18:16]} :
 (y<900) ? config_debug[15:0] :
 (y<960) ? config_debug[31:16] :
 (y<1020) ? config_debug[47:32] : {7'd0,config_debug[56:48]};
wire [3:0] debug_column=x/120;
wire [23:0] debug_color=debug_word[15-debug_column] ? 24'h00b000 : 24'hb00000;
wire [23:0] fallback_pixel;
test_pattern_generator_tpg fallback(.h_cnt(hc),.v_cnt(vc),.de(de),.pattern_sel(2'b00),.rgb(fallback_pixel));
always @(posedge pix_clk or negedge video_reset_n)begin
 if(!video_reset_n)begin hs_pipe<=0;vs_pipe<=0;de_pipe<=0;overlay_pipe<=0;fallback_0<=0;fallback_1<=0;fallback_2<=0;end
 else begin
  hs_pipe<={hs_pipe[1:0],hs};vs_pipe<={vs_pipe[1:0],vs};de_pipe<={de_pipe[1:0],de};
  overlay_pipe<={overlay_pipe[1:0],(de && y>=720)};
  fallback_0<=(de && y>=720) ? debug_color : fallback_pixel;fallback_1<=fallback_0;fallback_2<=fallback_1;
 end
end
assign hd_tx_pclk=pix_clk;
assign hd_tx_vs=vs_pipe[2];
assign hd_tx_hs=hs_pipe[2];
assign hd_tx_de=de_pipe[2];
assign hd_tx_data=de_pipe[2] ? ((frame_valid && !(DEBUG_OVERLAY && overlay_pipe[2])) ? stored_pixel : fallback_2) : 24'd0;
endmodule
