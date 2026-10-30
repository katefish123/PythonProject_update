`timescale 1ns/1ps
module tb_clocks;
 reg clkin1=0;always #18.518518 clkin1=~clkin1;
 wire clkout0,clkout57,lock;video_pll_27m_148m5 dut(.*);
 realtime pp=0,pc=0,dp,dc;integer np=0,nc=0;
 always @(posedge clkout0)if(lock)begin
  dp=$realtime-pp;if(np>20&&(dp<13.466||dp>13.470))$fatal(1,"PIXEL_PLL_PERIOD %f",dp);
  pp=$realtime;np=np+1;
 end
 always @(posedge clkout57)if(lock)begin
  dc=$realtime-pc;if(nc>20&&(dc<10.772||dc>10.777))$fatal(1,"PROCESSING_PLL_PERIOD %f",dc);
  pc=$realtime;nc=nc+1;
 end
 initial begin
  wait(lock);wait(np>=1000&&nc>=1000);
  $display("VIDEO_CLOCKS_PASS pixel_mhz=74.25 processing_mhz=92.8125 pixel_period_ns=%f processing_period_ns=%f pixel_samples=%0d proc_samples=%0d",dp,dc,np,nc);$finish;
 end
 initial begin #2000000;$fatal(1,"PLL_LOCK_TIMEOUT");end
endmodule
