`timescale 1ns/1ps
// Minimal reproduction of frozen V4S top memory_detail/screen_status expressions.
module tb_legacy_fault_red;
 reg clk=0,rst_n=0,align_error=0;reg[3:0]source_reason=0;reg[4:0]memory_detail=0;
 always #4 clk=~clk;
 always @(posedge clk or negedge rst_n)if(!rst_n)memory_detail<=0;else if(memory_detail==0&&align_error)memory_detail<=26;
 wire[4:0]screen_status=(source_reason==7&&memory_detail!=0)?memory_detail:{1'b0,source_reason};
 initial begin
  repeat(2)@(negedge clk);rst_n=1;align_error=1;@(negedge clk);align_error=0;
  repeat(2)@(negedge clk);source_reason=7;#1;
  if(screen_status!=7)$fatal(1,"HISTORY_OVERRIDES_CURRENT_SOURCE current_source=7 actual_display=%0d historical_detail=%0d",screen_status,memory_detail);
  $fatal(1,"legacy regression unexpectedly passed");
 end
endmodule
