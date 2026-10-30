`timescale 1ns/1ps
module tb_ddr_block_writer;
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0,start=0,abort_frame=0;
 reg [31:0] base=0;
 wire start_ready,block_ready,done,ok,busy;
 reg block_valid=0,block_last=0;
 reg [255:0] data=0; reg [31:0] strb=0;
 wire cmd_valid,cmd_write; wire [27:0] addr;
 wire [255:0] wd; wire [31:0] ws;
 reg cmd_ready=0,rsp_valid=0,rsp_write=1,fault=0;
 integer test_passed=0;
 ddr_block_writer dut(clk,rst_n,start,start_ready,base,abort_frame,
   block_valid,block_ready,data,strb,block_last,busy,done,ok,
   cmd_valid,cmd_ready,cmd_write,addr,wd,ws,rsp_valid,rsp_write,fault);
 task tick; begin @(posedge clk); #1; end endtask
 task reset; begin @(negedge clk);rst_n=0;start=0;abort_frame=0;block_valid=0;
  cmd_ready=0;rsp_valid=0;rsp_write=1;fault=0;tick;@(negedge clk);rst_n=1;tick;end endtask
 task begin_frame(input [31:0] b);begin
  @(negedge clk);base=b;start=1;tick;@(negedge clk);start=0;
 end endtask
 task send_block(input bit last);begin
  if(!block_ready)$fatal(1,"block unexpectedly blocked");
  @(negedge clk);data=256'h0123456789abcdef;strb=32'h000000ff;block_last=last;block_valid=1;
  tick;@(negedge clk);block_valid=0;
 end endtask
 task accept_cmd;begin @(negedge clk);cmd_ready=1;tick;@(negedge clk);cmd_ready=0;end endtask
 task respond;begin @(negedge clk);rsp_valid=1;tick;@(negedge clk);rsp_valid=0;end endtask
 initial begin
  reset;begin_frame(32'd8294400);send_block(0);
  repeat(4)begin tick;if(!cmd_valid||addr!=28'd2073600||wd!=data||ws!=strb||!cmd_write)
   $fatal(1,"byte address conversion or stalled command changed");end
  accept_cmd;repeat(3)begin tick;if(done||block_ready||!busy)$fatal(1,"completed before DDR response");end
  respond;if(done||!block_ready)$fatal(1,"nonfinal response handling");
  send_block(1);tick;if(addr!=28'd2073608)$fatal(1,"block stride is not eight words");
  accept_cmd;respond;if(!done||!ok||busy)$fatal(1,"final write not acknowledged");tick;
  reset;begin_frame(0);send_block(1);accept_cmd;
  @(negedge clk);abort_frame=1;tick;@(negedge clk);abort_frame=0;
  repeat(4)begin tick;if(done||!busy||start_ready)$fatal(1,"aborted slot released before drain");end
  respond;if(!done||ok)$fatal(1,"abort did not invalidate frame");
  reset;begin_frame(0);send_block(1);
  @(negedge clk);abort_frame=1;tick;
  if(!done||ok||cmd_valid)$fatal(1,"unaccepted command not canceled");
  reset;begin_frame(0);send_block(1);
  @(negedge clk);abort_frame=1;cmd_ready=1;tick;
  if(done||!busy)$fatal(1,"abort and command acceptance must drain");
  @(negedge clk);abort_frame=0;cmd_ready=0;respond;if(!done||ok)$fatal(1,"same-edge abort lost");
  reset;begin_frame(0);send_block(1);accept_cmd;
  @(negedge clk);fault=1;rsp_valid=1;tick;
  if(!done||ok)$fatal(1,"fault response published success");
  reset;begin_frame(0);send_block(1);accept_cmd;rsp_write=0;
  respond;if(!done||ok)$fatal(1,"read response accepted as write completion");
  reset;begin_frame(32'd4);tick;if(busy||cmd_valid)$fatal(1,"misaligned base accepted");
  reset;begin_frame(32'h40000000);tick;if(busy||cmd_valid)$fatal(1,"address truncation accepted");
  reset;begin_frame(32'h3fffffe0);send_block(0);accept_cmd;respond;
  if(!done||ok)$fatal(1,"address overflow must fail before next command");
  reset;begin_frame(0);send_block(1);
  @(negedge clk);cmd_ready=1;rsp_valid=1;tick;
  if(!done||!ok)$fatal(1,"zero-latency response lost");
  test_passed=1;$display("PASS_DDR_BLOCK_WRITER address stalls drain abort fault overflow immediate_response");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
