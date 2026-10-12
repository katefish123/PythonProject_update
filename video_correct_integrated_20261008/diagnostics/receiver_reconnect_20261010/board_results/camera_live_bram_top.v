`timescale 1ns/1ps
`default_nettype none
// Raw camera pixels in two BRAM banks, scaled 6x onto independent 1080p60 TX.
// Each source holds its diagnostic bundle until the next snapshot request.
module camera_live_bram_top (
 input wire sys_clk_27m,rst_n,hd_rx_pclk,hd_rx_vs,hd_rx_hs,hd_rx_de,
 input wire [23:0] hd_rx_data,
 output wire hd_tx_pclk,hd_reset_n,hd_scl,inout wire hd_sda,
 output reg hd_tx_vs,hd_tx_hs,hd_tx_de,output reg [23:0] hd_tx_data,
 output wire [7:0] led
);
 wire pix_clk,cfg_clk,pix_lock,cfg_lock;
 video_pll_27m_148m5 vp(.clkin1(sys_clk_27m),.clkout0(pix_clk),.lock(pix_lock));
 config_pll_27m_10m cp(.clkin1(sys_clk_27m),.clkout0(cfg_clk),.lock(cfg_lock));
 wire clocks_ready=rst_n&&pix_lock&&cfg_lock;
 wire cfg_rst_n,pix_rst_n,rx_rst_n,sys_rst_n;
 reset_sync cr(.clk(cfg_clk),.arst_n(clocks_ready),.rst_n(cfg_rst_n));
 reset_sync pr(.clk(pix_clk),.arst_n(clocks_ready),.rst_n(pix_rst_n));
 reset_sync rr(.clk(hd_rx_pclk),.arst_n(clocks_ready),.rst_n(rx_rst_n));
 reset_sync sr(.clk(sys_clk_27m),.arst_n(clocks_ready),.rst_n(sys_rst_n));
 reg [13:0] reset_count;
 always @(posedge cfg_clk or negedge cfg_rst_n) begin
  if(!cfg_rst_n)reset_count<=0;
  else if(reset_count<10000)reset_count<=reset_count+1'b1;
 end
 assign hd_reset_n=cfg_rst_n&&(reset_count==10000);
 wire rx_done,tx_done,ack_error,config_error,startup_retry_seen;
 wire [143:0] config_debug;
 hdmi_config_runtime_diag #(.TX_FIRST(1'b1)) config_bus(
  .cfg_clk(cfg_clk),.reset_n(hd_reset_n),.rx_done(rx_done),.tx_done(tx_done),
  .scl(hd_scl),.sda(hd_sda),.ack_error(ack_error),
  .config_error(config_error),.startup_retry_seen(startup_retry_seen),
  .debug_word(config_debug));

 reg de_q,hs_q,vs_q,de_prev,hs_prev,vs_prev;
 reg [23:0] rgb_q,sample_rgb;
 reg de_seen,vs_seen,hs_seen;
 reg [15:0] line_pixels,rx_width,active_lines,rx_height,vs_edges;
 reg [15:0] line_period,rx_line_period;
 reg line_period_valid;
 reg [7:0] alive_div;
 reg alive_toggle;
 always @(posedge hd_rx_pclk or negedge rx_rst_n) begin
  if(!rx_rst_n) begin
   de_q<=0;hs_q<=0;vs_q<=0;rgb_q<=0;de_prev<=0;hs_prev<=0;vs_prev<=0;
   de_seen<=0;vs_seen<=0;hs_seen<=0;sample_rgb<=0;
   line_pixels<=0;rx_width<=0;active_lines<=0;rx_height<=0;vs_edges<=0;
   line_period<=0;rx_line_period<=0;line_period_valid<=0;
   alive_div<=0;alive_toggle<=0;
  end else begin
   de_q<=hd_rx_de;hs_q<=hd_rx_hs;vs_q<=hd_rx_vs;rgb_q<=hd_rx_data;
   de_prev<=de_q;hs_prev<=hs_q;vs_prev<=vs_q;
   alive_div<=alive_div+1'b1;
   if(alive_div==8'hff)alive_toggle<=~alive_toggle;
   if(de_q) begin
    de_seen<=1;sample_rgb<=rgb_q;
    if(line_pixels!=16'hffff)line_pixels<=line_pixels+1'b1;
   end
   if(!de_q&&de_prev)begin
    rx_width<=line_pixels;line_pixels<=0;
    if(active_lines!=16'hffff)active_lines<=active_lines+1'b1;
   end
   if(line_period!=16'hffff)line_period<=line_period+1'b1;
   if(hs_q&&!hs_prev)begin
    hs_seen<=1;
    if(line_period_valid)rx_line_period<=line_period+1'b1;
    line_period<=0;line_period_valid<=1;
   end
   if(vs_q&&!vs_prev)begin
    vs_seen<=1;rx_height<=active_lines;active_lines<=0;
    if(vs_edges!=16'hffff)vs_edges<=vs_edges+1'b1;
   end
  end
 end
 wire [93:0] rx_debug={de_seen,vs_seen,hs_seen,rx_width,rx_height,
  rx_line_period,vs_edges,sample_rgb,vs_q,hs_q,de_q};

 (* ASYNC_REG="TRUE" *) reg [2:0] alive_sync;
 reg alive_last,clock_seen;
 reg [25:0] heartbeat;
 always @(posedge sys_clk_27m or negedge sys_rst_n) begin
  if(!sys_rst_n)begin alive_sync<=0;alive_last<=0;clock_seen<=0;heartbeat<=0;end
  else begin
   alive_sync<={alive_sync[1:0],alive_toggle};alive_last<=alive_sync[2];
   if(alive_last!=alive_sync[2])clock_seen<=1;
   heartbeat<=heartbeat+1'b1;
  end
 end

 wire [11:0] hc,vc;
 wire raw_hs,raw_vs,raw_de;
 video_timing_vtc #(.H_SYNC(12'd44),.H_BACK(12'd148),.H_ACTIVE(12'd1920),.H_FRONT(12'd88),
  .V_SYNC(12'd5),.V_BACK(12'd36),.V_ACTIVE(12'd1080),.V_FRONT(12'd4))
 timing(.clk(pix_clk),.rst_n(pix_rst_n),.h_cnt(hc),.v_cnt(vc),
  .hsync(raw_hs),.vsync(raw_vs),.de(raw_de));
 wire [11:0] x=hc-12'd192,y=vc-12'd41;
 reg raw_vs_prev,snapshot_request,rx_snapshot_request;
 (* ASYNC_REG="TRUE" *) reg [2:0] cfg_req_sync,rx_req_sync;
 reg cfg_ack,rx_ack;
 reg [143:0] cfg_hold;
 reg [93:0] rx_hold;
 always @(posedge cfg_clk or negedge cfg_rst_n)begin
  if(!cfg_rst_n)begin cfg_req_sync<=0;cfg_ack<=0;cfg_hold<=0;end
  else begin
   cfg_req_sync<={cfg_req_sync[1:0],snapshot_request};
   if(cfg_req_sync[2]!=cfg_ack)begin cfg_hold<=config_debug;cfg_ack<=cfg_req_sync[2];end
  end
 end
 always @(posedge hd_rx_pclk or negedge rx_rst_n)begin
  if(!rx_rst_n)begin rx_req_sync<=0;rx_ack<=0;rx_hold<=0;end
  else begin
   rx_req_sync<={rx_req_sync[1:0],rx_snapshot_request};
   if(rx_req_sync[2]!=rx_ack)begin rx_hold<=rx_debug;rx_ack<=rx_req_sync[2];end
  end
 end
 (* ASYNC_REG="TRUE" *) reg [2:0] cfg_ack_sync,rx_ack_sync,clock_seen_sync;
 reg cfg_ack_last,rx_ack_last,cfg_snapshot_valid,rx_snapshot_valid;
 reg [143:0] cfg_snapshot;
 reg [93:0] rx_snapshot;
 reg [319:0] status_frame;
 wire [15:0] flags={cfg_snapshot[143:136],clock_seen_sync[2],rx_snapshot[93:91],
  cfg_lock,pix_lock,cfg_snapshot_valid&&(cfg_ack_sync[2]==snapshot_request),
  rx_snapshot_valid&&(rx_ack_sync[2]==rx_snapshot_request)};
 wire frame_valid;
 wire [18:0] buffer_snapshot;
 reg [12:0] display_frame_count;
 wire [319:0] status_word={16'hD104,flags,cfg_snapshot[135:8],
  rx_snapshot[90:3],cfg_snapshot[7:0],16'hB401,15'd0,frame_valid,
  buffer_snapshot,display_frame_count};
 always @(posedge pix_clk or negedge pix_rst_n)begin
  if(!pix_rst_n)begin
   raw_vs_prev<=0;snapshot_request<=0;rx_snapshot_request<=0;
   cfg_ack_sync<=0;rx_ack_sync<=0;clock_seen_sync<=0;
   cfg_snapshot_valid<=0;rx_snapshot_valid<=0;
   cfg_ack_last<=0;rx_ack_last<=0;cfg_snapshot<=0;rx_snapshot<=0;status_frame<=0;
  end else begin
   raw_vs_prev<=raw_vs;
   cfg_ack_sync<={cfg_ack_sync[1:0],cfg_ack};rx_ack_sync<={rx_ack_sync[1:0],rx_ack};
   clock_seen_sync<={clock_seen_sync[1:0],clock_seen};
   cfg_ack_last<=cfg_ack_sync[2];rx_ack_last<=rx_ack_sync[2];
   if(cfg_ack_sync[2]!=cfg_ack_last)begin cfg_snapshot<=cfg_hold;cfg_snapshot_valid<=1;end
   if(rx_ack_sync[2]!=rx_ack_last)begin rx_snapshot<=rx_hold;rx_snapshot_valid<=1;end
   if(raw_vs&&!raw_vs_prev)begin
    status_frame<=status_word;snapshot_request<=~snapshot_request;
    // Never toggle a still-pending RX request: an absent clock must not
    // produce a false "response received" through toggle aliasing.
    if(rx_ack_sync[2]==rx_snapshot_request)rx_snapshot_request<=~rx_snapshot_request;
   end
  end
 end
 // C's real two-clock, two-bank pixel store; no simulated camera in hardware.
 wire [23:0] stored_pixel;
 wire [15:0] samples_written;
 wire [2:0] writer_flags;
 wire output_frame_start=raw_vs&&!raw_vs_prev;
 reg [8:0] scaled_x;
 reg [7:0] scaled_y;
 reg [15:0] read_address;
 reg [2:0] hs_pipe,vs_pipe,de_pipe;
 reg [23:0] fallback_0,fallback_1,fallback_2;
 wire buffer_snapshot_valid,buffer_snapshot_busy;
 cdc_snapshot #(.WIDTH(19)) buffer_observation(
  .src_clk(hd_rx_pclk),.src_reset_n(rx_rst_n),
  .src_data({writer_flags,samples_written}),
  .dst_clk(pix_clk),.dst_reset_n(pix_rst_n),.request(output_frame_start),
  .dst_data(buffer_snapshot),.valid(buffer_snapshot_valid),.busy(buffer_snapshot_busy));
 hdmi_bram_probe camera_store(
  .wr_clk(hd_rx_pclk),.wr_reset_n(rx_rst_n),.de(de_q),.pixel(rgb_q),
  .rd_clk(pix_clk),.rd_reset_n(pix_rst_n),.frame_start(output_frame_start),
  .rd_enable(de_pipe[1]),.rd_addr(de_pipe[1]?read_address:16'd0),
  .rd_pixel(stored_pixel),.frame_valid(frame_valid),
  .samples_written(samples_written),.writer_flags(writer_flags));
 wire [3:0] col=x/12'd120;
 wire [4:0] row=(y-12'd840)/12'd12;
 wire [8:0] bit_index=9'd319-{row,col};
 wire status_area=raw_de&&(y>=12'd840);
 // Without a fresh camera frame, show a diagnostic grid on a dark background.
 // Never substitute a test picture for actual camera pixels.
 wire [23:0] fallback_rgb=status_area?
  (status_frame[bit_index]?24'h00b000:24'hb00000):24'h100010;
 always @(posedge pix_clk or negedge pix_rst_n)begin
  if(!pix_rst_n)begin
   scaled_x<=0;scaled_y<=0;read_address<=0;
   hs_pipe<=0;vs_pipe<=0;de_pipe<=0;
   fallback_0<=0;fallback_1<=0;fallback_2<=0;display_frame_count<=0;
  end else begin
   scaled_x<=raw_de?x/6:0;scaled_y<=raw_de?y/6:0;
   read_address<=scaled_y*320+scaled_x;
   hs_pipe<={hs_pipe[1:0],raw_hs};vs_pipe<={vs_pipe[1:0],raw_vs};
   de_pipe<={de_pipe[1:0],raw_de};
   fallback_0<=fallback_rgb;fallback_1<=fallback_0;fallback_2<=fallback_1;
   if(output_frame_start)display_frame_count<=display_frame_count+1'b1;
  end
 end
 // Register the final pixel selection and its timing together before the pins.
 always @(posedge pix_clk or negedge pix_rst_n)begin
  if(!pix_rst_n)begin hd_tx_hs<=0;hd_tx_vs<=0;hd_tx_de<=0;hd_tx_data<=0;end
  else begin
   hd_tx_hs<=hs_pipe[2];hd_tx_vs<=vs_pipe[2];hd_tx_de<=de_pipe[2];
   hd_tx_data<=de_pipe[2]?(frame_valid?stored_pixel:fallback_2):24'd0;
  end
 end
 assign hd_tx_pclk=pix_clk;
 assign led={cfg_lock,config_error,frame_valid,de_seen,clock_seen,tx_done,rx_done,heartbeat[24]};
endmodule
`default_nettype wire
