`timescale 1ns/1ps
module tb_geometry_reset;
 reg rx=0,proc=0,run_rx=1;always #3.367 if(run_rx)rx=~rx;always #18.519 proc=~proc;
 reg rr=0,pr=0,pv=0,first=0,last=0,token=1,done=0;reg[23:0]rgb=0;
 wire mt,mid,mb,good;wire[95:0]corners;reg test_passed=0;
 capture_geometry #(.SRC_W(16),.SRC_H(8),.MIN_PIXELS(1),.MAX_PIXELS(64),.MAX_SPAN(16),.FIFO_ADDR_BITS(4)) dut(
  .rx_clk(rx),.rx_rst_n(rr),.proc_clk(proc),.proc_rst_n(pr),.sample_valid(pv),.sample_first(first),.sample_last(last),
  .sample_rgb(rgb),.sample_token(token),.sample_bank(1'b1),.rx_complete_toggle(done),
  .metadata_toggle(mt),.metadata_token(mid),.metadata_bank(mb),.metadata_ok(good),.metadata_corners(corners));
 task pixel(input integer k);
  begin @(negedge rx);pv=1;first=(k==0);last=(k==127);rgb=(k==17||k==30||k==110||k==97)?24'd0:24'h808080;end
 endtask
 task finish_frame;
  begin
   @(negedge rx);pv=0;first=0;last=0;repeat(4)@(negedge rx);done=token;
   wait(mt==1);@(negedge proc);
   if(!good||!mid||!mb||corners!=={12'd1,12'd1,12'd14,12'd1,12'd14,12'd6,12'd1,12'd6})$fatal(1,"reset/pause geometry identity or centroid good=%d token=%d bank=%d corners=%h",good,mid,mb,corners);
  end
 endtask
 initial begin
  repeat(5)@(negedge proc);rr=1;pr=1;repeat(20)@(negedge rx);
  for(integer k=0;k<64;k=k+1)pixel(k);
  @(negedge rx);pv=0;first=0;last=0;run_rx=0;
  repeat(30)@(negedge proc);if(mt!=0)$fatal(1,"RX pause published partial metadata");run_rx=1;
  for(integer k=64;k<128;k=k+1)pixel(k);finish_frame;
  repeat(20)@(negedge proc);token=0;done=1;
  for(integer k=0;k<40;k=k+1)pixel(k);
  @(negedge rx);pv=0;first=0;last=0;pr=0;
  repeat(8)@(negedge proc);
  if(mt||good)$fatal(1,"partial common reset did not flush metadata");
  token=1;done=0;pr=1;repeat(20)@(negedge rx);
  for(integer k=0;k<128;k=k+1)pixel(k);finish_frame;
  test_passed=1;$display("GEOMETRY_RESET_PASS RX_clock_pause no_partial_publish midframe_proc_reset common_flush recovery");$finish;
 end
 initial begin #300000;$fatal(1,"reset/pause timeout");end
endmodule
