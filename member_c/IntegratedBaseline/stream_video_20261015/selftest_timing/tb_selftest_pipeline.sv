`timescale 1ns/1ps
module tb_selftest_pipeline;
 reg clk=0,rst_n=0,enabled=0,ready=0,rsp=0,rw=0;
 reg [255:0] data=0;
 always #4 clk=~clk;
 wire passed,failed,cv,cw;wire[27:0]addr;wire[255:0]wd;wire[31:0]mask;
 ddr_self_test #(.BEATS(3),.BASE(28'h600000)) dut(clk,rst_n,enabled,passed,failed,cv,ready,cw,addr,wd,mask,rsp,rw,data);
 reg[255:0] mem[0:2];integer tests=0;
 task run_case(input integer badbeat,input integer badbit,input integer wrongtype,input integer pipelined);
 integer n,k;reg[255:0]word;
 begin
 @(negedge clk);rst_n=0;enabled=0;ready=0;rsp=0;
 repeat(3)@(negedge clk);rst_n=1;enabled=1;
 for(k=0;k<2;k=k+1)for(n=0;n<3;n=n+1)begin
  wait(cv);@(negedge clk);
  if(cw!==(k==0)||addr!==28'h600000+n*8||mask!==32'hffffffff)$fatal(1,"COMMAND_MISMATCH");
  if(k==0)mem[n]=wd;
  repeat(2)begin @(negedge clk);if(!cv)$fatal(1,"COMMAND_NOT_HELD");end
  ready=1;@(negedge clk);ready=0;repeat(2)@(negedge clk);
  word=mem[n];if(k==1&&n==badbeat)word[badbit]=~word[badbit];
  data=word;rw=(k==0);if(k==1&&n==2&&wrongtype)rw=1;
  rsp=1;@(negedge clk);rsp=0;data=~word;
  // Timing-specific requirement: no 256-bit response-to-final-status path.
  if(k==1&&n==2&&pipelined&&!wrongtype&&(passed||failed))$fatal(1,"RESPONSE_COMPARE_NOT_PIPELINED");
 end
 wait(passed||failed);@(negedge clk);
 if((badbeat>=0||wrongtype)?(!failed||passed):(!passed||failed))$fatal(1,"BAD_FINAL_STATUS");
 repeat(3)@(negedge clk);
 if((badbeat>=0||wrongtype)?(!failed||passed):(!passed||failed))$fatal(1,"STATUS_NOT_STICKY");
 tests=tests+1;
 end endtask
 integer bitno;
 initial begin
  run_case(-1,0,0,1);
  for(bitno=0;bitno<256;bitno=bitno+1)begin run_case(0,bitno,0,0);run_case(2,bitno,0,0);end
  run_case(1,127,0,0);run_case(-1,0,1,0);run_case(-1,0,0,1);
  $display("SELFTEST_PIPELINE_PASS cases=%0d",tests);$finish;
 end
 initial begin #10000000;$fatal(1,"TIMEOUT");end
endmodule
