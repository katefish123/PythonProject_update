`timescale 1ns/1ps
`ifndef ARBITER
`define ARBITER ddr_arbiter3_turnaround
`endif
module tb_turnaround_arbiter;
 reg clk=0,rst_n=0;always #4 clk=~clk;
 wire v,r0,r1,r2,s0,s1,s2;wire[27:0]addr;reg rsp=0;reg[1:0]delay_count=0;reg[27:0]expected_owner;
 integer n0=0,n1=0,n2=0,total=0,dual=0;reg display_on=0;
 `ARBITER #(.BALANCE_C01(1)) dut(.clk(clk),.rst_n(rst_n),.enabled(1'b1),
 .c0_valid(1'b1),.c0_write(1'b0),.c0_addr(28'd16),.c0_wdata(256'd0),.c0_wstrb(32'd0),.c0_ready(r0),.c0_rsp_valid(s0),.c0_rsp_write(),.c0_rdata(),
 .c1_valid(1'b1),.c1_write(1'b1),.c1_addr(28'd32),.c1_wdata(256'd0),.c1_wstrb(32'd0),.c1_ready(r1),.c1_rsp_valid(s1),.c1_rsp_write(),.c1_rdata(),
 .c2_valid(display_on),.c2_write(1'b0),.c2_addr(28'd48),.c2_wdata(256'd0),.c2_wstrb(32'd0),.c2_ready(r2),.c2_rsp_valid(s2),.c2_rsp_write(),.c2_rdata(),
 .cmd_valid(v),.cmd_ready(1'b1),.cmd_write(),.cmd_addr(addr),.cmd_wdata(),.cmd_wstrb(),.rsp_valid(rsp),.rsp_write(1'b0),.rsp_rdata(256'd0));
 always @(posedge clk)if(rst_n)begin
  rsp<=0;
  if(rsp&&((s0!== (expected_owner==16))||(s1!== (expected_owner==32))||(s2!== (expected_owner==48))))$fatal(1,"response ownership changed");
  if(v&&rsp)dual=dual+1;
  if(v)begin
   if(delay_count!=0)$fatal(1,"overlapping owner");
   if(display_on&&!r2)$fatal(1,"display lost priority");
   n0=n0+r0;n1=n1+r1;n2=n2+r2;total=total+1;expected_owner=addr;delay_count<=2;
  end else if(delay_count==1)begin delay_count<=0;rsp<=1;end
  else if(delay_count!=0)delay_count<=delay_count-1;

 end
 initial begin
  repeat(3)@(negedge clk);rst_n=1;
  wait(total==16);@(negedge clk);
  if(n0!=8||n1!=8)$fatal(1,"FAIRNESS_REQUIRED c0=%0d c1=%0d",n0,n1);
  display_on=1;wait(total==20);@(negedge clk);display_on=0;
  wait(total==28);@(negedge clk);
  if(n0!=12||n1!=12||n2!=4)$fatal(1,"fairness/recovery");
  if(dual<20)$fatal(1,"TURNAROUND_REQUIRED dual=%0d",dual);
  $display("FAIR_ARBITER_PASS alternating=24 display_priority=4 response_owner=28");$finish;
 end
 initial begin #10000;$fatal(1,"timeout");end
endmodule
