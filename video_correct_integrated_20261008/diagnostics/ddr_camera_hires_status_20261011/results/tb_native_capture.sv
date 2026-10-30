`timescale 1ns/1ps
module tb_native_capture;
 reg rx_clk=0,ui_clk=0,reset_n=0,vs=0,de=0,request=0;
 reg [23:0] pixel=0;
 always #3.37037 rx_clk=~rx_clk;
 always #4 ui_clk=~ui_clk;
 wire rx_done,rx_ok,full,empty,we,re,rvalid,done,good,cv,cw;
 wire [284:0] wd,rd;wire [27:0] ca;wire [255:0] cd;wire [31:0] mask;
 wire ready;reg response=0,pending=0;integer tick=0,delay_count=0,packets=0;
 reg test_passed=0;
 function [23:0] encoded(input integer x,input integer y);encoded=(y<<12)|x;endfunction
 ddr_snapshot_capture #(.IN_W(1920),.IN_H(1080),.SRC_W(960),.SRC_H(540)) capture(
  .rx_clk(rx_clk),.rx_rst_n(reset_n),.rx_vs(vs),.rx_de(de),.rx_rgb(pixel),.request_toggle(request),
  .rx_complete_toggle(rx_done),.capture_ok(rx_ok),.fifo_wr_en(we),.fifo_wr_data(wd),.fifo_full(full),.diagnostic_snapshot());
 async_packet_fifo #(.DATA_WIDTH(285),.ADDR_BITS(10)) fifo(.wr_clk(rx_clk),.rd_clk(ui_clk),.rst_n(reset_n),
  .wr_en(we),.wr_data(wd),.full(full),.rd_en(re),.rd_data(rd),.rd_valid(rvalid),.empty(empty));
 ddr_capture_writer #(.SRC_W(960),.SRC_H(540)) writer(.ui_clk(ui_clk),.ui_rst_n(reset_n),.request_toggle(request),
  .rx_complete_toggle(rx_done),.rx_capture_ok(rx_ok),.fifo_empty(empty),.fifo_rd_data(rd),.fifo_rd_valid(rvalid),.fifo_rd_en(re),
  .cmd_valid(cv),.cmd_ready(ready),.cmd_write(cw),.cmd_addr(ca),.cmd_wdata(cd),.cmd_wstrb(mask),
  .rsp_valid(response),.rsp_write(1'b1),.complete_toggle(done),.capture_ok(good),.diagnostic_snapshot());
 assign ready=reset_n&&!pending&&(tick%17>=5);
 always @(posedge ui_clk)begin
  tick<=tick+1;response<=0;
  if(cv&&ready)begin
   if(!cw||ca!=packets*8||mask!==32'hffffffff)$fatal(1,"bad native capture command at packet %0d",packets);
   for(integer lane=0;lane<8;lane=lane+1)begin
    if(cd[lane*32+:32]!=={8'd0,encoded(((packets*8+lane)%960)*2,((packets*8+lane)/960)*2)})$fatal(1,"native stride/packet mismatch packet=%0d lane=%0d",packets,lane);
   end
   packets<=packets+1;delay_count<=3+tick%4;pending<=1;
  end
  if(pending)begin
   if(delay_count==0)begin response<=1;pending<=0;end else delay_count<=delay_count-1;
  end
 end
 initial begin
  repeat(10)@(negedge rx_clk);reset_n=1;request=1;repeat(20)@(negedge rx_clk);
  vs=1;repeat(5)@(negedge rx_clk);vs=0;
  for(integer y=0;y<1080;y=y+1)begin
   for(integer x=0;x<1920;x=x+1)begin de=1;pixel=encoded(x,y);@(negedge rx_clk);end
   de=0;repeat(280)@(negedge rx_clk);
  end
  vs=1;repeat(5)@(negedge rx_clk);vs=0;
  wait(done==request);#1;
  if(!good||!rx_ok||packets!=64800)$fatal(1,"high-resolution source incomplete good=%b rx_ok=%b packets=%0d",good,rx_ok,packets);
  test_passed=1;$display("NATIVE_CAPTURE_PASS pixels=518400 packets=64800 stride2=1 fifo1024=1 delayed_writer=1");$finish;
 end
 initial begin #80000000;$fatal(1,"native capture timeout");end
endmodule
