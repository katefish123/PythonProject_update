`timescale 1ns/1ps
module tb_marker_detector;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,pv=0,fs=0,fe=0;
 reg [11:0] x=0,y=0;reg [23:0] rgb=0;
 wire [191:0] marker_state;
 wire cv,reject,drop,busy;wire [11:0] x0,y0,x1,y1,x2,y2,x3,y3;
 marker_detector #(.SRC_W(640),.SRC_H(480)) dut(clk,rst_n,pv,fs,fe,x,y,rgb,cv,reject,drop,busy,x0,y0,x1,y1,x2,y2,x3,y3,marker_state);
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
 task frame(input integer omit_last_yellow,input integer scatter,input integer bad_coordinate);
  integer bx,by,index;
  begin
   index=0;
   for(integer c=0;c<4;c=c+1)begin
    bx=(c==1||c==2)?52:4;by=(c>=2)?36:4;
    for(integer k=0;k<16;k=k+1)begin
     @(negedge clk);pv=1;fs=(index==0);fe=(c==3&&k==15);x=bx+k%4;y=by+k/4;
     case(c)
      0:rgb=24'ha00000;1:rgb=24'h008c00;2:rgb=24'ha08c00;3:rgb=24'h0000a0;
     endcase
     if(omit_last_yellow&&c==2&&k==15)rgb=0;
     if(scatter&&c==0&&k==15)x=300;
     if(bad_coordinate&&c==0&&k==15)x=640;
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
  frame(0,0,0);
  if(marker_state[175:112]!={16'd16,16'd16,16'd16,16'd16}||marker_state[191:176]!=16'h0008)
   $fatal(1,"actual inclusive marker snapshot incorrect");
  frame(0,0,0); // second snapshot arrives while divider busy
  repeat(400)@(negedge clk);
  if(seen!=1||dropped!=1)$fatal(1,"busy snapshot drop");
  frame(1,0,0);if(marker_state[143:128]!=15||marker_state[179])$fatal(1,"missing yellow threshold report");repeat(5)@(negedge clk);
  frame(0,1,0);repeat(5)@(negedge clk);
  frame(0,0,1);repeat(5)@(negedge clk);
  if(rejected!=3)$fatal(1,"marker rejection counts %0d",rejected);
  frame(0,0,0);repeat(400)@(negedge clk);
  if(seen!=2)$fatal(1,"marker did not recover");
  frame(0,0,0);repeat(20)@(negedge clk);rst_n=0;repeat(3)@(negedge clk);rst_n=1;repeat(400)@(negedge clk);
  if(cv||busy||seen!=2)$fatal(1,"marker reset abort");
  test_passed=1;$display("MARKER_STATUS_PASS valid=2 rejected=3 dropped=1");$finish;
 end
 initial begin #100000;$fatal(1,"MARKER timeout");end
endmodule
