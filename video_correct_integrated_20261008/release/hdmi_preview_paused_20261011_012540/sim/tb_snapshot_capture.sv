`timescale 1ns/1ps
module tb_snapshot_capture;
 reg rx_clk=0,rd_clk=0;
 always #3.5 rx_clk=~rx_clk;
 always #5.5 rd_clk=~rd_clk;
 reg rx_rst_n=0,rd_rst_n=0,rx_vs=0,rx_de=0;
 reg [23:0] rx_rgb=0;
 reg request_toggle=0,rd_valid=0;
 reg [23:0] rd_addr=0;
 wire complete_toggle,capture_ok,rd_rsp_valid;
 wire [23:0] rd_rgb;
 integer x,y,i,reads=0;
 reg passed=0;
 snapshot_capture #(.IN_W(8),.IN_H(4),.DECIMATE(2)) dut(
  .rx_clk(rx_clk),.rx_rst_n(rx_rst_n),.rx_vs(rx_vs),.rx_de(rx_de),.rx_rgb(rx_rgb),
  .request_toggle(request_toggle),.complete_toggle(complete_toggle),.capture_ok(capture_ok),
  .rd_clk(rd_clk),.rd_rst_n(rd_rst_n),.rd_valid(rd_valid),.rd_addr(rd_addr),
  .rd_rsp_valid(rd_rsp_valid),.rd_rgb(rd_rgb));
 function [23:0] pixel(input integer xx,input integer yy);
  pixel=24'h120000+yy*16+xx;
 endfunction
 task send_line(input integer yy,input integer width);
  begin
   @(negedge rx_clk);rx_de=1;
   for(x=0;x<width;x=x+1)begin
    rx_rgb=pixel(x,yy);@(negedge rx_clk);
   end
   rx_de=0;rx_rgb=0;repeat(2)@(negedge rx_clk);
  end
 endtask
 task start_capture;
  begin
   @(negedge rx_clk);request_toggle=~request_toggle;
   repeat(5)@(negedge rx_clk);
   rx_vs=1;@(negedge rx_clk);rx_vs=0;repeat(2)@(negedge rx_clk);
  end
 endtask
 task read_and_check;
  begin
   reads=0;
   for(i=0;i<8;i=i+1)begin
    @(negedge rd_clk);rd_addr=i;rd_valid=1;
    @(posedge rd_clk);#1;
    if(!rd_rsp_valid)$fatal(1,"missing read response at address %0d",i);
    if(rd_rgb!==pixel((i%4)*2,(i/4)*2))$fatal(1,"capture mismatch addr=%0d got=%h expected=%h",i,rd_rgb,pixel((i%4)*2,(i/4)*2));
    reads=reads+1;
   end
   @(negedge rd_clk);rd_valid=0;
  end
 endtask
 initial begin
  repeat(4)@(negedge rx_clk);rx_rst_n=1;rd_rst_n=1;
  start_capture();
  for(y=0;y<4;y=y+1)send_line(y,8);
  wait(complete_toggle==request_toggle);#1;
  if(!capture_ok)$fatal(1,"complete frame was rejected");
  read_and_check();
  $display("SNAPSHOT_FULL_FRAME_PASS pixels=%0d async_clocks=1",reads);
  // An incomplete frame must complete as rejected when its next VS boundary arrives.
  start_capture();
  send_line(0,8);send_line(1,5);
  @(negedge rx_clk);rx_vs=1;@(negedge rx_clk);rx_vs=0;
  wait(complete_toggle==request_toggle);#1;
  if(capture_ok)$fatal(1,"short frame incorrectly published");
  $display("SNAPSHOT_SHORT_FRAME_REJECT_PASS");
  passed=1;$finish;
 end
 initial begin #200000;$fatal(1,"snapshot test timeout");end
endmodule
