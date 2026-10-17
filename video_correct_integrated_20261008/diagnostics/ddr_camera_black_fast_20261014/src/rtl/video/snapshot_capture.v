`timescale 1ns/1ps
`default_nettype none
// Snapshot + integer decimation. A single source bank is locked after capture.
// Control is a toggle handshake: do not change request until processing finishes.
// Complete input dimensions are checked. Bad/short frames are not published.
module snapshot_capture #(
 parameter IN_W=1920,IN_H=1080,DECIMATE=6,
 parameter SRC_W=IN_W/DECIMATE,SRC_H=IN_H/DECIMATE
)(
 input wire rx_clk,rx_rst_n,rx_vs,rx_de,input wire [23:0] rx_rgb,
 input wire request_toggle,output reg complete_toggle,output reg capture_ok,
 input wire rd_clk,rd_rst_n,rd_valid,input wire [23:0] rd_addr,
 output reg rd_rsp_valid,output reg [23:0] rd_rgb
);
 localparam N=SRC_W*SRC_H;
 (* ram_style="block" *) reg [23:0] memory[0:N-1];
 (* ASYNC_REG="TRUE" *) reg [2:0] req_sync;
 reg vs_d,de_d,active,bad;
 reg [11:0] x,y;
 reg [11:0] sub_x,sub_y;
 reg [23:0] count;
 wire write_pixel=active&&rx_de&&sub_x==0&&sub_y==0&&x<IN_W&&y<IN_H&&count<N;
 always @(posedge rx_clk)if(write_pixel)memory[count]<=rx_rgb;
 always @(posedge rd_clk)if(rd_valid)rd_rgb<=memory[rd_addr];
 always @(posedge rd_clk or negedge rd_rst_n)begin
  if(!rd_rst_n)rd_rsp_valid<=0;else rd_rsp_valid<=rd_valid;
 end
 always @(posedge rx_clk or negedge rx_rst_n)begin
  if(!rx_rst_n)begin
   req_sync<=0;complete_toggle<=0;capture_ok<=0;vs_d<=0;de_d<=0;
   active<=0;bad<=0;x<=0;y<=0;sub_x<=0;sub_y<=0;count<=0;
  end else begin
   req_sync<={req_sync[1:0],request_toggle};vs_d<=rx_vs;de_d<=rx_de;
   if(rx_vs&&!vs_d)begin
    if(active)begin // previous frame ended early
     active<=0;capture_ok<=0;complete_toggle<=req_sync[2];
    end else if(req_sync[2]!=complete_toggle)begin
     active<=1;bad<=0;x<=0;y<=0;sub_x<=0;sub_y<=0;count<=0;capture_ok<=0;
    end
   end else if(active)begin
    if(rx_de)begin
     x<=x+1;
     if(x>=IN_W)bad<=1;
     if(sub_x==DECIMATE-1)sub_x<=0;else sub_x<=sub_x+1;
     if(write_pixel)count<=count+1;
    end
    if(de_d&&!rx_de)begin
     if(x!=IN_W)bad<=1;
     x<=0;sub_x<=0;
     if(y==IN_H-1)begin
      active<=0;capture_ok<=!bad&&x==IN_W&&count==N;
      complete_toggle<=req_sync[2];
     end else begin
      y<=y+1;
      if(sub_y==DECIMATE-1)sub_y<=0;else sub_y<=sub_y+1;
     end
    end
   end
  end
 end
endmodule
`default_nettype wire
