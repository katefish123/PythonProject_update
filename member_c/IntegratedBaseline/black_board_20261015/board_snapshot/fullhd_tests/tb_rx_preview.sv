`timescale 1ns/1ps
module tb_rx_preview;
 reg test_passed=0;
 reg rc=0,pc=0,rst=0,vs=0,de=0,sd=0,ss=0;reg[23:0]data=0;reg[11:0]x=0,y=0;
 always #3 rc=~rc;always #5 pc=~pc;
 wire[23:0]rgb;wire valid,bad;wire[12:0]ow,oh;
 rx_preview #(.IN_W(16),.IN_H(8),.DECIMATE(2)) dut(rc,rst,vs,de,data,pc,rst,sd,ss,x,y,rgb,valid,ow,oh,bad);
 task pulse_vs;begin @(negedge rc);vs=1;@(negedge rc);vs=0;repeat(4)@(negedge rc);end endtask
 task frame(input[23:0]color,input integer width);begin
  pulse_vs;
  for(integer j=0;j<8;j=j+1)begin
   for(integer i=0;i<width;i=i+1)begin @(negedge rc);de=1;data=color;end
   @(negedge rc);de=0;repeat(3)@(negedge rc);
  end
  pulse_vs;
 end endtask
 task acknowledge;begin repeat(6)@(negedge pc);ss=1;@(negedge pc);ss=0;repeat(8)@(negedge rc);end endtask
 task check(input[23:0]expected);begin
  for(integer j=0;j<8;j=j+1)for(integer i=0;i<16;i=i+1)begin
   @(negedge pc);sd=1;x=i;y=j;@(negedge pc);
   if(rgb!==expected)$fatal(1,"preview pixel %d,%d actual=%h expected=%h",i,j,rgb,expected);
  end sd=0;
 end endtask
 initial begin #30;rst=1;repeat(4)@(negedge rc);frame(24'h123456,16);if(valid)$fatal(1,"published before frame boundary");acknowledge;
 if(!valid||bad||ow!=16||oh!=8)$fatal(1,"valid frame was not accepted");check(24'h123456);
 frame(24'habcdef,15);acknowledge;if(!bad)$fatal(1,"short input was accepted");check(24'h123456);
 frame(24'h789abc,16);acknowledge;check(24'h789abc);
 rst=0;#20;if(valid)$fatal(1,"reset did not invalidate preview");
 test_passed=1;$display("PREVIEW_COMPLETE_BAD_FRAME_RECOVERY_PASS");$finish;end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
