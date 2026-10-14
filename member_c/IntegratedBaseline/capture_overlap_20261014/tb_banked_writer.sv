`timescale 1ns/1ps
module tb_banked_writer;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,request=0,rx_done=0,rx_ok=1;
 reg [27:0] base=512;wire pop,cmd,write,complete,good;wire [27:0] addr;wire [255:0] data;wire [31:0] mask;
 reg fvalid=0;reg [284:0] packet=0;integer fed=0,accepted=0,delay_count=0,run_no=0;
 reg pending=0,rsp=0;integer tick=0;
 wire ready=rst_n&&!pending&&(tick%7>=3);
 reg test_passed=0;
`ifdef LEGACY_WRITER
 ddr_capture_writer #(.SRC_W(16),.SRC_H(1)) dut(
`else
 ddr_capture_writer_banked #(.SRC_W(16),.SRC_H(1)) dut(.base_word_addr(base),
`endif
 .ui_clk(clk),.ui_rst_n(rst_n),.request_toggle(request),.rx_complete_toggle(rx_done),.rx_capture_ok(rx_ok),
 .fifo_rd_en(pop),.fifo_empty(fed>=2),.fifo_rd_data(packet),.fifo_rd_valid(fvalid),
 .cmd_valid(cmd),.cmd_ready(ready),.cmd_write(write),.cmd_addr(addr),.cmd_wdata(data),.cmd_wstrb(mask),
 .rsp_valid(rsp),.rsp_write(1'b1),.complete_toggle(complete),.capture_ok(good));
 reg blocked=0;reg [283:0] held=0;
 always @(posedge clk)begin
  tick<=tick+1;fvalid<=0;rsp<=0;
  if(!rst_n)begin pending<=0;blocked<=0;end
  else begin
   if(pop)begin packet<={request,28'(fed*8),256'(fed+17)};fed=fed+1;fvalid<=1;end
   if(blocked&&(!cmd||{addr,data}!==held))$fatal(1,"banked writer payload changed under backpressure");
   blocked<=cmd&&!ready;held<={addr,data};
   if(cmd&&ready)begin
    if(addr!==(run_no==0?512:1024)+accepted*8)$fatal(1,"BANK_BASE_NOT_LATCHED addr=%0d run=%0d beat=%0d",addr,run_no,accepted);
    if(data!==256'(accepted+17)||mask!==32'hffffffff||!write)$fatal(1,"banked writer data mismatch");
    accepted=accepted+1;pending<=1;delay_count<=6;
   end
   if(pending)begin if(delay_count>0)delay_count<=delay_count-1;else begin pending<=0;rsp<=1;end end
  end
 end
 initial begin
  repeat(5)@(negedge clk);rst_n=1;request=1;rx_done=1;
  wait(accepted==1);@(negedge clk);base=1024;
  wait(complete==1);@(negedge clk);if(!good||accepted!=2)$fatal(1,"first bank frame not drained");
  run_no=1;fed=0;accepted=0;request=0;rx_done=0;
  wait(complete==0);@(negedge clk);if(!good||accepted!=2)$fatal(1,"second bank frame not drained");
  test_passed=1;$display("BANKED_WRITER_PASS latched_base responses backpressure two_banks");$finish;
 end
 initial begin #100000;$fatal(1,"banked writer timeout");end
endmodule
