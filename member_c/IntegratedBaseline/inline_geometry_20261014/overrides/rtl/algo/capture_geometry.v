`timescale 1ns/1ps
`default_nettype none
// Observe the exact accepted source-pixel stream. Reuse the original detector
// arithmetic; attach the capture transaction identity to its held result.
module capture_geometry #(
 parameter SRC_W=1920,SRC_H=1080,MIN_PIXELS=64,MAX_PIXELS=16384,MAX_SPAN=256,
 parameter BLACK_RMIN=0,BLACK_RMAX=64,BLACK_GMIN=0,BLACK_GMAX=64,BLACK_BMIN=0,BLACK_BMAX=64,
 // Inclusive, non-overlapping windows in source coordinates; P0/P1/P2/P3 = TL/TR/BR/BL.
 // Integer division places the center column/row of an odd source in right/bottom ROIs.
 parameter P0_XMIN=0,P0_XMAX=SRC_W/2-1,P0_YMIN=0,P0_YMAX=SRC_H/2-1,
 parameter P1_XMIN=SRC_W/2,P1_XMAX=SRC_W-1,P1_YMIN=0,P1_YMAX=SRC_H/2-1,
 parameter P2_XMIN=SRC_W/2,P2_XMAX=SRC_W-1,P2_YMIN=SRC_H/2,P2_YMAX=SRC_H-1,
 parameter P3_XMIN=0,P3_XMAX=SRC_W/2-1,P3_YMIN=SRC_H/2,P3_YMAX=SRC_H-1
)(
 input wire rx_clk,rx_rst_n,sample_valid,sample_first,sample_last,
 input wire [23:0] sample_rgb,
 input wire sample_token,sample_bank,rx_complete_toggle,
 output reg metadata_toggle,metadata_token,metadata_bank,metadata_ok,
 output reg [95:0] metadata_corners
);
 reg active,held_token,held_bank,last_seen;
 reg [11:0] x,y;
 wire [11:0] pixel_x=sample_first?12'd0:x,pixel_y=sample_first?12'd0:y;
 wire valid,reject_frame,dropped,busy;
 wire [11:0] x0,y0,x1,y1,x2,y2,x3,y3;
 marker_detector #(.SRC_W(SRC_W),.SRC_H(SRC_H),.MIN_PIXELS(MIN_PIXELS),
  .MAX_PIXELS(MAX_PIXELS),.MAX_SPAN(MAX_SPAN),
  .BLACK_RMIN(BLACK_RMIN),.BLACK_RMAX(BLACK_RMAX),.BLACK_GMIN(BLACK_GMIN),.BLACK_GMAX(BLACK_GMAX),.BLACK_BMIN(BLACK_BMIN),.BLACK_BMAX(BLACK_BMAX),.P0_XMIN(P0_XMIN),.P0_XMAX(P0_XMAX),.P0_YMIN(P0_YMIN),.P0_YMAX(P0_YMAX),.P1_XMIN(P1_XMIN),.P1_XMAX(P1_XMAX),.P1_YMIN(P1_YMIN),.P1_YMAX(P1_YMAX),.P2_XMIN(P2_XMIN),.P2_XMAX(P2_XMAX),.P2_YMIN(P2_YMIN),.P2_YMAX(P2_YMAX),.P3_XMIN(P3_XMIN),.P3_XMAX(P3_XMAX),.P3_YMIN(P3_YMIN),.P3_YMAX(P3_YMAX)) detector(
  .clk(rx_clk),.rst_n(rx_rst_n),.pixel_valid(sample_valid),.frame_start(sample_valid&&sample_first),
  .frame_end(sample_valid&&sample_last),.pixel_x(pixel_x),.pixel_y(pixel_y),.rgb(sample_rgb),
  .corners_valid(valid),.frame_reject(reject_frame),.frame_dropped(dropped),.busy(busy),
  .x0(x0),.y0(y0),.x1(x1),.y1(y1),.x2(x2),.y2(y2),.x3(x3),.y3(y3));
 always @(posedge rx_clk or negedge rx_rst_n)begin
  if(!rx_rst_n)begin
   active<=0;held_token<=0;held_bank<=0;last_seen<=0;x<=0;y<=0;
   metadata_toggle<=0;metadata_token<=0;metadata_bank<=0;metadata_ok<=0;metadata_corners<=0;
  end else begin
   if(sample_valid)begin
    if(sample_first)begin
     active<=1;held_token<=sample_token;held_bank<=sample_bank;last_seen<=sample_last;
    end else if(sample_last)last_seen<=1;
    if(pixel_x==SRC_W-1)begin x<=0;y<=pixel_y+1'b1;end
    else begin x<=pixel_x+1'b1;y<=pixel_y;end
   end
   if(active)begin
    if(valid||reject_frame||dropped||
       (rx_complete_toggle==held_token&&!last_seen&&!(sample_valid&&sample_last)))begin
     metadata_toggle<=~metadata_toggle;metadata_token<=held_token;metadata_bank<=held_bank;
     metadata_ok<=valid&&!reject_frame&&!dropped&&last_seen;
     metadata_corners<=valid?{x0,y0,x1,y1,x2,y2,x3,y3}:96'd0;
     active<=0;
    end
   end
  end
 end
endmodule
`default_nettype wire
