`timescale 1ns/1ps
module tb_banked_burst_writer;
 reg clk=0;always #4 clk=~clk;
 reg rst=0,request=0,rx_done=0,rx_ok=1;reg[3:0]rx_reason=0;
 reg[27:0]base=0,expected_base=0;integer available=0,index=0,tick=0,commands=0,left=0;
 reg[284:0]packets[0:8];reg rv=0;reg[284:0]rd=0;
 wire re,cv,cw,complete,good;wire[27:0]ca;wire[255:0]cd;wire[2047:0]cb;wire[31:0]mask;wire[3:0]reason;
 reg pending=0,rsp=0,blocked=0;reg[2075:0]held=0;reg test_passed=0;
 wire ready=rst&&!pending&&(tick%9>=5);
 ddr_capture_writer_banked #(.SRC_W(64),.SRC_H(1),.BURST_BEATS(8)) dut(
  .ui_clk(clk),.ui_rst_n(rst),.base_word_addr(base),.request_toggle(request),.rx_complete_toggle(rx_done),.rx_capture_ok(rx_ok),.rx_failure_reason(rx_reason),
  .fifo_empty(index>=available),.fifo_rd_data(rd),.fifo_rd_valid(rv),.fifo_rd_en(re),
  .cmd_valid(cv),.cmd_ready(ready),.cmd_write(cw),.cmd_addr(ca),.cmd_wdata(cd),.cmd_burst_data(cb),.cmd_wstrb(mask),
  .rsp_valid(rsp),.rsp_write(1'b1),.complete_toggle(complete),.capture_ok(good),.failure_reason(reason));
 always @(posedge clk)begin
  tick<=tick+1;rv<=0;rsp<=0;
  if(!rst)begin pending<=0;blocked<=0;end
  else begin
   if(re&&index<available)begin rd<=packets[index];index=index+1;rv<=1;end
   if(blocked&&(!cv||{ca,cb}!==held))$fatal(1,"banked burst changed under command stall");
   blocked<=cv&&!ready;held<={ca,cb};
   if(cv&&ready)begin
    if(ca!==expected_base||!cw||mask!==32'hffffffff||pending)$fatal(1,"burst bank/base/ownership mismatch");
    for(integer k=0;k<8;k=k+1)if(cb[k*256+:256]!==256'h100+k)$fatal(1,"atomic payload mismatch");
    if(cd!==256'h100)$fatal(1,"first beat mismatch");
    commands=commands+1;pending<=1;left<=32;
   end
   if(pending)begin
    if(left>0)left<=left-1;else begin pending<=0;rsp<=1;end
   end
  end
 end
 task load(input integer count,input integer stale);
  begin
   index=0;available=count+stale;
   if(stale)packets[0]={!request,28'd0,256'hbad};
   for(integer k=0;k<count;k=k+1)packets[k+stale]={request,28'(k*8),256'(256'h100+k)};
  end
 endtask
 task full_frame(input[27:0]newbase,input integer stale);
  integer before_cmd;reg old_complete;begin
   @(negedge clk);old_complete=complete;before_cmd=commands;
   request=~request;base=newbase;expected_base=newbase;rx_ok=1;rx_reason=0;load(8,stale);
   repeat(12)@(negedge clk);base=28'h0100000;rx_done=request;
   wait(commands==before_cmd+1);repeat(5)@(negedge clk);
   if(complete!==old_complete)$fatal(1,"early capture completion");
   wait(complete==request);@(negedge clk);
   if(!good||reason!=0||commands!=before_cmd+1)$fatal(1,"banked burst did not recover/drain");
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst=1;repeat(5)@(negedge clk);
  full_frame(0,0);full_frame(28'h0800000,1);
  @(negedge clk);request=~request;base=0;expected_base=0;rx_ok=0;rx_reason=13;load(3,0);
  repeat(20)@(negedge clk);rx_done=request;wait(complete==request);@(negedge clk);
  if(good||reason!=13||commands!=2)$fatal(1,"partial batch rejection lost");
  full_frame(28'h0800000,0);
  test_passed=1;$display("BANKED_BURST_WRITER_PASS both_source_banks base_latch full_payload stalls stale_token partial_batch recovery");$finish;
 end
 initial begin #100000;$fatal(1,"banked burst writer timeout");end
endmodule
