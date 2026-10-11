`timescale 1ns/1ps
// One clock domain, 8 pixels per 256-bit block. Lane zero is the first pixel.
module rgb888_block_packer(input clk,rst_n,in_valid,output in_ready,input [23:0] in_rgb,
 input in_last,in_abort,output reg out_valid,input out_ready,output reg [255:0] out_data,
 output reg [31:0] out_strb,output reg out_last);
reg [255:0] assembling;
reg [2:0] count;
reg [255:0] next_data;
always @*begin
 next_data=assembling;
 next_data[count*32+:32]={8'd0,in_rgb};
end
assign in_ready=(!out_valid || out_ready) && !in_abort;
always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
  assembling<=0;count<=0;out_valid<=0;out_data<=0;out_strb<=0;out_last<=0;
 end else if(in_abort)begin
  assembling<=0;count<=0;out_valid<=0;out_data<=0;out_strb<=0;out_last<=0;
 end else begin
  if(out_ready)out_valid<=0;
  if(in_valid && in_ready)begin
   if(in_last || count==7)begin
    out_data<=next_data;out_valid<=1;out_last<=in_last;
    out_strb<=32'hffffffff >> ((7-count)*4);
    assembling<=0;count<=0;
   end else begin assembling<=next_data;count<=count+1'b1;end
  end
 end
end
endmodule
