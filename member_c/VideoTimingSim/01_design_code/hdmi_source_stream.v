`timescale 1ns/1ps
// RX-domain adapter. Inputs are already source-synchronous registers.
// Positive VS edge arms a new frame; startup/reconnect partial frames are dropped.
module hdmi_source_stream #(parameter WIDTH=1920,HEIGHT=1080)(
 input clk,rst_n,link_valid,vs,de,input [23:0] rgb,
 output reg src_valid,src_frame_start,src_frame_end,
 output reg [11:0] src_x,src_y,output reg [23:0] src_rgb,output reg frame_abort);
reg vs_prev,de_prev,armed,busy,complete;
reg [12:0] column;
reg [11:0] row;
always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin
  vs_prev<=0;de_prev<=0;armed<=0;busy<=0;complete<=0;column<=0;row<=0;
  src_valid<=0;src_frame_start<=0;src_frame_end<=0;src_x<=0;src_y<=0;src_rgb<=0;frame_abort<=0;
 end else begin
  vs_prev<=vs;de_prev<=de;
  src_valid<=0;src_frame_start<=0;src_frame_end<=0;frame_abort<=0;
  if(!link_valid) begin
   frame_abort<=busy;armed<=0;busy<=0;complete<=0;column<=0;row<=0;de_prev<=0;
  end else if(vs && !vs_prev) begin
   frame_abort<=busy || de;
   armed<=!de;busy<=0;complete<=0;column<=0;row<=0;de_prev<=0;
  end else if(armed) begin
   if(de) begin
    if(complete || column>=WIDTH || row>=HEIGHT) begin
     frame_abort<=1;armed<=0;busy<=0;
    end else begin
     src_valid<=1;src_rgb<=rgb;src_x<=column[11:0];src_y<=row;
     src_frame_start<=(column==0 && row==0);
     src_frame_end<=(column==WIDTH-1 && row==HEIGHT-1);
     column<=column+1'b1;busy<=1;
     if(column==WIDTH-1 && row==HEIGHT-1)begin complete<=1;busy<=0;end
    end
   end else if(de_prev) begin
    if(column!=WIDTH)begin frame_abort<=1;armed<=0;busy<=0;end
    else begin column<=0;if(!complete)row<=row+1'b1;end
   end
  end
 end
end
endmodule
