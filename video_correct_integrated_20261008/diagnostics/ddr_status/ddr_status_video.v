`timescale 1ns/1ps
`default_nettype none

// Standalone TX raster and status strip. It has no RX or DDR dependency.
module ddr_status_video #(
 parameter H_SYNC=44,H_BACK=148,H_ACTIVE=1920,H_FRONT=88,
 parameter V_SYNC=5,V_BACK=36,V_ACTIVE=1080,V_FRONT=4,
 parameter STATUS_X=128,STATUS_Y=1040,CELL_W=96,CELL_H=32,CELL_GAP=16
)(
 input wire pix_clk,reset_n,
 input wire [14:0] status_async,
 output reg hsync,vsync,de,
 output reg [23:0] rgb,
 output wire pix_clk_out
);
 localparam H_TOTAL=H_SYNC+H_BACK+H_ACTIVE+H_FRONT;
 localparam V_TOTAL=V_SYNC+V_BACK+V_ACTIVE+V_FRONT;
 reg [11:0] hc,vc;
 (* ASYNC_REG="TRUE" *) reg [14:0] status_meta,status_sync1,status_sync2;
 reg [14:0] status_frame;
 wire active=(hc>=H_SYNC+H_BACK)&&(hc<H_SYNC+H_BACK+H_ACTIVE)&&
             (vc>=V_SYNC+V_BACK)&&(vc<V_SYNC+V_BACK+V_ACTIVE);
 wire [11:0] ax=hc-(H_SYNC+H_BACK);
 wire [11:0] ay=vc-(V_SYNC+V_BACK);
 reg [23:0] color_now;
 integer n;
 always @* begin
  if(ax<H_ACTIVE/8) color_now=24'hffffff;
  else if(ax<H_ACTIVE*2/8) color_now=24'hffff00;
  else if(ax<H_ACTIVE*3/8) color_now=24'h00ffff;
  else if(ax<H_ACTIVE*4/8) color_now=24'h00ff00;
  else if(ax<H_ACTIVE*5/8) color_now=24'hff00ff;
  else if(ax<H_ACTIVE*6/8) color_now=24'hff0000;
  else if(ax<H_ACTIVE*7/8) color_now=24'h0000ff;
  else color_now=24'h000000;
  if(active && ay>=STATUS_Y && ay<STATUS_Y+CELL_H) begin
   color_now=24'h000000;
   for(n=0;n<15;n=n+1)
    if(ax>=STATUS_X+n*(CELL_W+CELL_GAP) && ax<STATUS_X+n*(CELL_W+CELL_GAP)+CELL_W)
     color_now=status_frame[14-n]?24'h00ff00:24'hff0000;
  end
  if(!active) color_now=24'h000000;
 end
 always @(posedge pix_clk or negedge reset_n) begin
  if(!reset_n) begin
   hc<=0;vc<=0;status_meta<=0;status_sync1<=0;status_sync2<=0;status_frame<=0;
   hsync<=0;vsync<=0;de<=0;rgb<=0;
  end else begin
   if(hc==H_TOTAL-1) begin
    hc<=0;
    if(vc==V_TOTAL-1)vc<=0;else vc<=vc+1'b1;
   end else hc<=hc+1'b1;
   status_meta<=status_async;status_sync1<=status_meta;status_sync2<=status_sync1;
   if(hc==0 && vc==0)status_frame<=status_sync2;
   hsync<=(hc<H_SYNC);vsync<=(vc<V_SYNC);de<=active;rgb<=color_now;
  end
 end
 assign pix_clk_out=pix_clk;
endmodule

`default_nettype wire
