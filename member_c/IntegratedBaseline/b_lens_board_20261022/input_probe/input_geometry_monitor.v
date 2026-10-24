`timescale 1ns/1ps
// Read-only measurement. No assumed input frame rate, width or height.
module input_geometry_monitor(input wire clk,rst_n,vs,de,output reg[159:0]snapshot);
 reg vd,dd,started;reg[15:0]width,lines,last_width,min_width,max_width;
 reg[31:0]pixels,period,frames;
 wire boundary=vs&&!vd;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin vd<=0;dd<=0;started<=0;width<=0;lines<=0;last_width<=0;min_width<=16'hffff;max_width<=0;pixels<=0;period<=0;frames<=0;snapshot<=0;end
  else begin
   vd<=vs;dd<=de;period<=period+1'b1;
   if(boundary)begin
    if(started)begin snapshot<={frames+1'b1,period+1'b1,max_width,min_width,pixels,lines,last_width};frames<=frames+1'b1;end
    started<=1;period<=0;width<=0;lines<=0;last_width<=0;min_width<=16'hffff;max_width<=0;pixels<=0;
   end else if(started)begin
    if(de)begin if(width!=16'hffff)width<=width+1'b1;pixels<=pixels+1'b1;end
    else if(dd)begin
     last_width<=width;if(width<min_width)min_width<=width;if(width>max_width)max_width<=width;
     if(lines!=16'hffff)lines<=lines+1'b1;width<=0;
    end
   end
  end
 end
endmodule
