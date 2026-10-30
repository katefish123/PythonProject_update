`timescale 1ns/1ps
`default_nettype none
// Actual measured state overlaid below y720; one registered stage aligns RGB/DE/HS/VS.
module ddr_status_overlay #(parameter CELL_W=120,CELL_H=10,STATUS_Y=720)(
 input wire clk,reset_n,in_hs,in_vs,in_de,input wire [23:0] in_rgb,
 input wire [511:0] status_word,output reg snapshot_request,
 output reg out_hs,out_vs,out_de,output reg [23:0] out_rgb
);
 reg vs_previous,de_previous;
 reg [11:0] x,y;
 reg [511:0] status_frame;
 wire status_area=in_de&&(y>=STATUS_Y)&&(y<STATUS_Y+32*CELL_H)&&(x<16*CELL_W);
 wire [8:0] bit_index=9'd511-((y-STATUS_Y)/CELL_H)*16-(x/CELL_W);
 always @(posedge clk or negedge reset_n)begin
  if(!reset_n)begin
   x<=0;y<=0;vs_previous<=0;de_previous<=0;status_frame<=0;snapshot_request<=0;
   out_hs<=0;out_vs<=0;out_de<=0;out_rgb<=0;
  end else begin
   vs_previous<=in_vs;de_previous<=in_de;snapshot_request<=0;
   if(in_vs&&!vs_previous)begin x<=0;y<=0;status_frame<=status_word;snapshot_request<=1;end
   else if(in_de)x<=x+1'b1;
   else if(de_previous)begin x<=0;y<=y+1'b1;end
   out_hs<=in_hs;out_vs<=in_vs;out_de<=in_de;
   out_rgb<=in_de?(status_area?(status_frame[bit_index]?24'h00b000:24'hb00000):in_rgb):24'd0;
  end
 end
endmodule
`default_nettype wire
