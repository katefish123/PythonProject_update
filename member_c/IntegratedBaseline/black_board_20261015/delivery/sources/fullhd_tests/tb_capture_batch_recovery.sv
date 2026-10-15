`timescale 1ns/1ps
module tb_capture_batch_recovery;
 reg clk=0,rst_n=0,request=0,rx_done=0,rx_ok=0;always #4 clk=~clk;
 reg[3:0]rx_reason=0;reg[284:0]packets[0:7];integer available=0,index=0;
 wire empty=index>=available;wire re;reg rv=0;reg[284:0]rd=0;
 wire cv,cw,done,good;wire[27:0]ca;wire[255:0]cd;wire[2047:0]cb;wire[31:0]mask;wire[3:0]reason;
 reg rsp=0;reg pending=0;integer delay_left=0,commands=0;reg test_passed=0;
 ddr_capture_writer #(.SRC_W(64),.SRC_H(1),.BURST_BEATS(8)) dut(.ui_clk(clk),.ui_rst_n(rst_n),
  .request_toggle(request),.rx_complete_toggle(rx_done),.rx_capture_ok(rx_ok),.rx_failure_reason(rx_reason),
  .fifo_empty(empty),.fifo_rd_data(rd),.fifo_rd_valid(rv),.fifo_rd_en(re),
  .cmd_valid(cv),.cmd_ready(1'b1),.cmd_write(cw),.cmd_addr(ca),.cmd_wdata(cd),.cmd_burst_data(cb),.cmd_wstrb(mask),
  .rsp_valid(rsp),.rsp_write(1'b1),.complete_toggle(done),.capture_ok(good),.failure_reason(reason));
 always @(posedge clk)begin
  if(!rst_n)begin rv<=0;pending<=0;rsp<=0;commands<=0;delay_left<=0;end
  else begin
   rv<=0;rsp<=0;
   if(re&&!empty)begin rd<=packets[index];index=index+1;rv<=1;end
   if(cv)begin
    if(pending||ca!=0||!cw||mask!==32'hffffffff)$fatal(1,"BATCH_COMMAND");
    for(integer k=0;k<8;k=k+1)if(cb[k*256+:256]!==256'h100+k)$fatal(1,"BATCH_PAYLOAD");
    if(cd!==256'h100)$fatal(1,"FIRST_BEAT");
    commands<=commands+1;pending<=1;delay_left<=20;
   end
   if(pending)begin if(delay_left>0)delay_left<=delay_left-1;else begin pending<=0;rsp<=1;end end
  end
 end
 task load(input reg token,input integer count);
  begin
   index=0;available=count;
   for(integer k=0;k<count;k=k+1)packets[k]={token,28'(k*8),256'(256'h100+k)};
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;repeat(5)@(negedge clk);
  load(1,3);request=1;rx_ok=0;rx_reason=13;repeat(20)@(negedge clk);rx_done=1;
  wait(done==1);if(good||reason!=13||commands!=0)$fatal(1,"PARTIAL_BAD_FRAME_NOT_REJECTED");
  @(negedge clk);load(0,8);request=0;rx_ok=1;rx_reason=0;repeat(25)@(negedge clk);rx_done=0;
  wait(commands==1);repeat(5)@(negedge clk);if(done!=1||good)$fatal(1,"EARLY_BURST_ACK");
  wait(done==0);if(!good||reason!=0)$fatal(1,"GOOD_FRAME_RECOVERY");
  @(negedge clk);load(1,8);request=1;rx_done=1;wait(commands==2);repeat(3)@(negedge clk);
  rst_n=0;repeat(3)@(negedge clk);request=0;rx_done=0;available=0;index=0;rst_n=1;repeat(5)@(negedge clk);
  if(cv||good||done||reason)$fatal(1,"OUTSTANDING_RESET_FLUSH");
  load(1,8);request=1;rx_done=1;rx_ok=1;rx_reason=0;
  wait(done==1);if(!good||commands!=1)$fatal(1,"RESET_RECOVERY");
  test_passed=1;$display("CAPTURE_BATCH_PARTIAL_RESET_RECOVERY_PASS");$finish;
 end
 initial begin #20000;$fatal(1,"BATCH_RECOVERY_TIMEOUT");end
endmodule
