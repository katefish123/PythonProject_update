`timescale 1ns/1ps
module tb_marker_detector;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,pv=0,fs=0,fe=0;
 reg [11:0] x=0,y=0;reg [23:0] rgb=0;
 wire cv,reject,drop,busy;wire [11:0] x0,y0,x1,y1,x2,y2,x3,y3;
 // Small source keeps all four default ROIs covered by a compact test stream.
 marker_detector #(.SRC_W(64),.SRC_H(48),.MAX_PIXELS(32),.MAX_SPAN(8))
  dut(clk,rst_n,pv,fs,fe,x,y,rgb,cv,reject,drop,busy,x0,y0,x1,y1,x2,y2,x3,y3);
 integer seen=0,rejected=0,dropped=0;
 reg test_passed=0;
 always @(posedge clk)begin
  #1;
  if(rst_n&&cv)begin
   if({x0,y0,x1,y1,x2,y2,x3,y3}!=={12'd6,12'd6,12'd54,12'd6,12'd54,12'd38,12'd6,12'd38})$fatal(1,"marker centroid/last pixel");
   seen=seen+1;
  end
  if(rst_n&&reject)rejected=rejected+1;
  if(rst_n&&drop)dropped=dropped+1;
 end
 // mode 1: missing point; 2: scatter; 3: out of bounds; 4: excess pixels;
 // mode 5: old four-color markers. All other streams use one black RGB value.
 task frame(input [23:0] color,input integer mode);
  integer bx,by,index,side,total;
  begin
   index=0;side=(mode==4)?6:4;total=side*side;
   for(integer c=0;c<4;c=c+1)begin
    bx=(c==1||c==2)?52:4;by=(c>=2)?36:4;
    for(integer k=0;k<total;k=k+1)begin
     @(negedge clk);pv=1;fs=(index==0);fe=(c==3&&k==total-1);x=bx+k%side;y=by+k/side;rgb=color;
     if(mode==1&&c==2&&k==15)rgb=24'hffffff;
     if(mode==2&&c==0&&k==15)x=20;
     if(mode==3&&c==0&&k==15)x=64;
     if(mode==5)begin
      case(c)
       0:rgb=24'ha00000;1:rgb=24'h008c00;2:rgb=24'ha08c00;3:rgb=24'h0000a0;
      endcase
     end
     index=index+1;
     // Valid bubbles within a frame must not change sums or counts.
     if(k==7)begin @(negedge clk);pv=0;fs=0;fe=0;end
    end
   end
   @(negedge clk);pv=0;fs=0;fe=0;
  end
 endtask
 initial begin
  repeat(3)@(negedge clk);rst_n=1;
  frame(24'h404040,0);frame(24'h000000,0); // inclusive upper threshold, then busy snapshot drop
  repeat(400)@(negedge clk);
  if(seen!=1||dropped!=1||rejected!=0)$fatal(1,"black marker/busy snapshot: valid=%0d dropped=%0d rejected=%0d",seen,dropped,rejected);
  frame(24'h000000,1);repeat(5)@(negedge clk);
  frame(24'h000000,2);repeat(5)@(negedge clk);
  frame(24'h000000,3);repeat(5)@(negedge clk);
  frame(24'h410000,0);repeat(5)@(negedge clk);
  frame(24'h004100,0);repeat(5)@(negedge clk);
  frame(24'h000041,0);repeat(5)@(negedge clk);
  frame(24'h000000,5);repeat(5)@(negedge clk);
  frame(24'h000000,4);repeat(5)@(negedge clk);
  frame(24'hffffff,0);repeat(5)@(negedge clk);
  if(rejected!=9||seen!=1)$fatal(1,"marker rejection counts %0d",rejected);
  frame(24'h000000,0);repeat(400)@(negedge clk);
  if(seen!=2)$fatal(1,"marker did not recover/pure black");
  frame(24'h000000,0);repeat(20)@(negedge clk);rst_n=0;repeat(3)@(negedge clk);rst_n=1;repeat(400)@(negedge clk);
  if(cv||busy||seen!=2)$fatal(1,"marker reset abort");
  test_passed=1;$display("MARKER_PASS valid=2 rejected=9 dropped=1 black_upper=64 channel_65_rejected=3");$finish;
 end
 initial begin #100000;$fatal(1,"MARKER timeout");end
endmodule
