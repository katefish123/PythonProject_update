`timescale 1ns/1ps
// Integration test against member B's actual marker_detector, not a substitute.
module tb_source_stream_marker;
reg clk=0,rst=0,vs=0,de=0;
reg [23:0] rgb=0;
always #5 clk=~clk;
wire valid,sof,eof,abort_frame,cv,reject,dropped,busy;
wire [11:0] x,y,x0,y0,x1,y1,x2,y2,x3,y3;
wire [23:0] pixel;
integer seen=0,test_passed=0;
hdmi_source_stream #(.WIDTH(32),.HEIGHT(24)) stream(
 clk,rst,1'b1,vs,de,rgb,valid,sof,eof,x,y,pixel,abort_frame);
marker_detector #(.SRC_W(32),.SRC_H(24),.MIN_PIXELS(4),.MAX_PIXELS(8),.MAX_SPAN(2)) marker(
 clk,rst,valid,sof,eof,x,y,pixel,cv,reject,dropped,busy,x0,y0,x1,y1,x2,y2,x3,y3);
always @(negedge clk)begin
 if(abort_frame || reject || dropped)$fatal(1,"unexpected frame failure");
 if(cv)begin
  // B rounds centroids to nearest integer: a 2x2 block at 2..3 gives 3.
  if({x0,y0,x1,y1,x2,y2,x3,y3}!=={12'd3,12'd3,12'd27,12'd3,12'd27,12'd19,12'd3,12'd19})
   $fatal(1,"C to B centroid mismatch %0d,%0d %0d,%0d %0d,%0d %0d,%0d",x0,y0,x1,y1,x2,y2,x3,y3);
  seen=seen+1;
 end
end
integer row,col,f;
initial begin
 repeat(3)@(negedge clk);rst=1;
 for(f=0;f<2;f=f+1)begin
  @(negedge clk);vs=1;@(negedge clk);vs=0;
  for(row=0;row<24;row=row+1)begin
   for(col=0;col<32;col=col+1)begin
    @(negedge clk);de=1;rgb=0;
    if(row>=2&&row<4&&col>=2&&col<4)rgb=24'hff0000;
    if(row>=2&&row<4&&col>=26&&col<28)rgb=24'h00ff00;
    if(row>=18&&row<20&&col>=26&&col<28)rgb=24'hffff00;
    if(row>=18&&row<20&&col>=2&&col<4)rgb=24'h0000ff;
   end
   @(negedge clk);de=0;repeat(3)@(negedge clk);
  end
  repeat(500)@(negedge clk);
 end
 if(seen!=2)$fatal(1,"missing marker results %0d",seen);
 test_passed=1;$display("PASS_C_TO_B_MARKER frames=2 corners=2");$finish;
end
initial begin #100000;$fatal(1,"integration timeout");end
endmodule
