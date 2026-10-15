`timescale 1ns/1ps
`default_nettype none
// Preserve B's detector arithmetic in the 27MHz domain. Pixels with no possible
// black ROI hit contribute nothing to B statistics and need not cross domains.
// Framing and abort events always cross; overflow retires invalid, never stale.
module capture_geometry #(
 parameter SRC_W=1920,SRC_H=1080,MIN_PIXELS=64,MAX_PIXELS=16384,MAX_SPAN=256,FIFO_ADDR_BITS=9,
 parameter BLACK_RMIN=0,BLACK_RMAX=64,BLACK_GMIN=0,BLACK_GMAX=64,BLACK_BMIN=0,BLACK_BMAX=64,
 parameter P0_XMIN=0,P0_XMAX=SRC_W/2-1,P0_YMIN=0,P0_YMAX=SRC_H/2-1,
 parameter P1_XMIN=SRC_W/2,P1_XMAX=SRC_W-1,P1_YMIN=0,P1_YMAX=SRC_H/2-1,
 parameter P2_XMIN=SRC_W/2,P2_XMAX=SRC_W-1,P2_YMIN=SRC_H/2,P2_YMAX=SRC_H-1,
 parameter P3_XMIN=0,P3_XMAX=SRC_W/2-1,P3_YMIN=SRC_H/2,P3_YMAX=SRC_H-1
)(
 input wire rx_clk,rx_rst_n,proc_clk,proc_rst_n,
 input wire sample_valid,sample_first,sample_last,input wire [23:0] sample_rgb,
 input wire sample_token,sample_bank,rx_complete_toggle,
 output reg metadata_toggle,metadata_token,metadata_bank,metadata_ok,
 output reg [95:0] metadata_corners
);
 wire shared_arst_n=rx_rst_n&&proc_rst_n;
 reg [1:0] rx_release,proc_release;
 always @(posedge rx_clk or negedge shared_arst_n)begin
  if(!shared_arst_n)rx_release<=0;else rx_release<={rx_release[0],1'b1};
 end
 always @(posedge proc_clk or negedge shared_arst_n)begin
  if(!shared_arst_n)proc_release<=0;else proc_release<={proc_release[0],1'b1};
 end
 wire rx_local_rst_n=rx_release[1],proc_local_rst_n=proc_release[1];
 // Cut the source capture counter/compare path before ROI selection and
 // FIFO pointer logic. This delays every pixel and its framing equally.
 reg tap_valid,tap_first,tap_last,tap_token,tap_bank;reg [23:0] tap_rgb;
 always @(posedge rx_clk or negedge rx_local_rst_n)begin
  if(!rx_local_rst_n)begin tap_valid<=0;tap_first<=0;tap_last<=0;tap_token<=0;tap_bank<=0;tap_rgb<=0;end
  else begin
   tap_valid<=sample_valid;tap_first<=sample_first;tap_last<=sample_last;
   tap_token<=sample_token;tap_bank<=sample_bank;tap_rgb<=sample_rgb;
  end
 end
 reg [11:0] x,y;
 reg rx_active,rx_token,rx_bank,start_sent,rx_overflow,tail_pending;
 reg [53:0] tail_data;
 wire [11:0] px=tap_first?12'd0:x,py=tap_first?12'd0:y;
 wire black=(tap_rgb[23:16]>=BLACK_RMIN)&&(tap_rgb[23:16]<=BLACK_RMAX)&&
  (tap_rgb[15:8]>=BLACK_GMIN)&&(tap_rgb[15:8]<=BLACK_GMAX)&&
  (tap_rgb[7:0]>=BLACK_BMIN)&&(tap_rgb[7:0]<=BLACK_BMAX);
 wire roi=(px>=P0_XMIN&&px<=P0_XMAX&&py>=P0_YMIN&&py<=P0_YMAX)||
  (px>=P1_XMIN&&px<=P1_XMAX&&py>=P1_YMIN&&py<=P1_YMAX)||
  (px>=P2_XMIN&&px<=P2_XMAX&&py>=P2_YMIN&&py<=P2_YMAX)||
  (px>=P3_XMIN&&px<=P3_XMAX&&py>=P3_YMIN&&py<=P3_YMAX);
 wire contributes=black&&roi;
 wire drop_pixels=tap_first?1'b0:rx_overflow;
 wire live_event=tap_valid&&(tap_first||tap_last||contributes);
 wire abort_event=rx_active&&(rx_complete_toggle==rx_token)&&!tap_valid;
 wire terminal_event=abort_event||(tap_valid&&tap_last);
 wire [53:0] live_data={contributes&&!drop_pixels,drop_pixels,
  tap_first||(tap_last&&!start_sent),tap_last,tap_token,tap_bank,px,py,tap_rgb};
 wire [53:0] abort_data={1'b0,1'b1,!start_sent,1'b1,rx_token,rx_bank,48'd0};
 wire fifo_full,fifo_empty,fifo_rvalid,fifo_rd_en;
 wire [53:0] fifo_rdata;
 wire wants_live=live_event&&(!drop_pixels||tap_last);
 wire fifo_wr_en=rx_local_rst_n&&!fifo_full&&(tail_pending||abort_event||wants_live);
 wire [53:0] fifo_wdata=tail_pending?tail_data:abort_event?abort_data:live_data;
 wire current_written=fifo_wr_en&&!tail_pending;
 async_packet_fifo #(.DATA_WIDTH(54),.ADDR_BITS(FIFO_ADDR_BITS)) selected_pixels(
  .wr_clk(rx_clk),.rd_clk(proc_clk),.rst_n(shared_arst_n),
  .wr_en(fifo_wr_en),.wr_data(fifo_wdata),.full(fifo_full),
  .rd_en(fifo_rd_en),.rd_data(fifo_rdata),.rd_valid(fifo_rvalid),.empty(fifo_empty));
 always @(posedge rx_clk or negedge rx_local_rst_n)begin
  if(!rx_local_rst_n)begin
   x<=0;y<=0;rx_active<=0;rx_token<=0;rx_bank<=0;start_sent<=0;
   rx_overflow<=0;tail_pending<=0;tail_data<=0;
  end else begin
   if(tail_pending&&fifo_wr_en)tail_pending<=0;
   if(tap_valid)begin
    if(tap_first)begin
     rx_active<=1;rx_token<=tap_token;rx_bank<=tap_bank;
     start_sent<=0;rx_overflow<=0;
    end
    if(px==SRC_W-1)begin x<=0;y<=py+1'b1;end
    else begin x<=px+1'b1;y<=py;end
   end
   if(live_event&&!current_written)rx_overflow<=1;
   if(current_written&&wants_live&&live_data[51])start_sent<=1;
   if(terminal_event)begin
    rx_active<=0;
    if(!current_written)begin
     tail_pending<=1;
     // The terminal may itself be lost to a full FIFO. Force abort and
     // retain SOF if none was delivered, so a short/overflow frame retires.
     tail_data<=abort_event?abort_data:
      {1'b0,1'b1,!start_sent,1'b1,tap_token,tap_bank,48'd0};
    end
   end
  end
 end

 reg pop_pending,waiting_result,frame_active,frame_bad,held_token,held_bank;
 wire packet=fifo_rvalid&&pop_pending;
 assign fifo_rd_en=proc_local_rst_n&&!fifo_empty&&!pop_pending&&!waiting_result;
 wire valid,reject_frame,dropped,busy;
 wire [11:0] x0,y0,x1,y1,x2,y2,x3,y3;
 marker_detector #(.SRC_W(SRC_W),.SRC_H(SRC_H),.MIN_PIXELS(MIN_PIXELS),.MAX_PIXELS(MAX_PIXELS),.MAX_SPAN(MAX_SPAN),
  .BLACK_RMIN(BLACK_RMIN),.BLACK_RMAX(BLACK_RMAX),.BLACK_GMIN(BLACK_GMIN),.BLACK_GMAX(BLACK_GMAX),.BLACK_BMIN(BLACK_BMIN),.BLACK_BMAX(BLACK_BMAX),
  .P0_XMIN(P0_XMIN),.P0_XMAX(P0_XMAX),.P0_YMIN(P0_YMIN),.P0_YMAX(P0_YMAX),
  .P1_XMIN(P1_XMIN),.P1_XMAX(P1_XMAX),.P1_YMIN(P1_YMIN),.P1_YMAX(P1_YMAX),
  .P2_XMIN(P2_XMIN),.P2_XMAX(P2_XMAX),.P2_YMIN(P2_YMIN),.P2_YMAX(P2_YMAX),
  .P3_XMIN(P3_XMIN),.P3_XMAX(P3_XMAX),.P3_YMIN(P3_YMIN),.P3_YMAX(P3_YMAX)) detector(
  .clk(proc_clk),.rst_n(proc_local_rst_n),.pixel_valid(packet&&fifo_rdata[53]),
  .frame_start(packet&&fifo_rdata[51]),.frame_end(packet&&fifo_rdata[50]),
  .pixel_x(fifo_rdata[47:36]),.pixel_y(fifo_rdata[35:24]),.rgb(fifo_rdata[23:0]),
  .corners_valid(valid),.frame_reject(reject_frame),.frame_dropped(dropped),.busy(busy),
  .x0(x0),.y0(y0),.x1(x1),.y1(y1),.x2(x2),.y2(y2),.x3(x3),.y3(y3));
 always @(posedge proc_clk or negedge proc_local_rst_n)begin
  if(!proc_local_rst_n)begin
   pop_pending<=0;waiting_result<=0;frame_active<=0;frame_bad<=0;held_token<=0;held_bank<=0;
   metadata_toggle<=0;metadata_token<=0;metadata_bank<=0;metadata_ok<=0;metadata_corners<=0;
  end else begin
   if(fifo_rd_en)pop_pending<=1;
   if(packet)begin
    pop_pending<=0;
    if(fifo_rdata[51]||!frame_active)begin
     held_token<=fifo_rdata[49];held_bank<=fifo_rdata[48];frame_active<=1;
     frame_bad<=!fifo_rdata[51]||fifo_rdata[52];
    end else if(fifo_rdata[52])frame_bad<=1;
    if(fifo_rdata[50])waiting_result<=1;
   end
   if(waiting_result&&(valid||reject_frame||dropped))begin
    metadata_toggle<=~metadata_toggle;metadata_token<=held_token;metadata_bank<=held_bank;
    metadata_ok<=valid&&!reject_frame&&!dropped&&!frame_bad;
    metadata_corners<=valid?{x0,y0,x1,y1,x2,y2,x3,y3}:96'd0;
    frame_active<=0;waiting_result<=0;
   end
  end
 end
endmodule
`default_nettype wire
