`timescale 1ns/1ps
module tb_board_recovery;
 reg cfg_clk=0;always #5 cfg_clk=~cfg_clk;
 reg external_rst_n=0,fault_request_async=0,ddr_ready_async=0;
 wire memory_release_n,recovering,exhausted;wire[7:0]recovery_count;wire[2:0]state;
 board_recovery_reset #(.HOLD_CYCLES(8),.LOCK_TIMEOUT(40),.SETTLE_CYCLES(8),.MAX_RETRIES(3)) dut(.*);
 task tick;begin @(posedge cfg_clk);#1;@(negedge cfg_clk);end endtask
 task await_run;integer n;begin n=0;while(recovering&&n<80)begin tick();n=n+1;end if(recovering)$fatal(1,"RUN not reached");end endtask
 initial begin
  repeat(3)tick();external_rst_n=1;repeat(5)tick();
  if(!memory_release_n||recovery_count!=0)$fatal(1,"cold startup incorrectly held");
  ddr_ready_async=1;await_run();
  // A real integration supplies an epoch latch, held until common reset.
  for(integer k=1;k<=3;k=k+1)begin
   fault_request_async=1;wait(!memory_release_n);#1;
   if(recovery_count!=k||!recovering)$fatal(1,"recovery count");
   fault_request_async=0;ddr_ready_async=0;
   repeat(6)begin tick();if(memory_release_n)$fatal(1,"reset hold shorter than configured");end
   wait(memory_release_n);ddr_ready_async=1;await_run();
  end
  fault_request_async=1;wait(exhausted);repeat(20)tick();
  if(memory_release_n||recovery_count!=3)$fatal(1,"retry exhaustion is not a protected stop");
  external_rst_n=0;tick();fault_request_async=0;ddr_ready_async=0;external_rst_n=1;repeat(50)tick();
  if(recovery_count<1)$fatal(1,"training timeout did not retry");
  external_rst_n=0;tick();if(memory_release_n||exhausted||recovery_count!=0)$fatal(1,"external reset must reset budget/history control");
  $display("PASS FULL_RESET_HOLD_READY_FENCE_RETRY_BUDGET_TRAIN_TIMEOUT_MANUAL_RESET");$finish;
 end
 initial begin #10000;$fatal(1,"timeout");end
endmodule
