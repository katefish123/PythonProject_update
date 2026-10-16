`timescale 1ns/1ps
module tb_native_service;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,cmd_valid=0,cmd_ready=0,awvalid=0,awready=0,wready=0,wlast=0,arvalid=0,arready=0,rvalid=0,rlast=0;
 wire[31:0]max_aw,max_first_w,max_w_gap,max_first_r,max_r_gap,max_cmd_wait;wire[3:0]stage;
 native_service_monitor dut(.*);
 task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 initial begin
 repeat(3)tick();rst_n=1;tick();
 awvalid=1;cmd_valid=1;repeat(5)tick();
 if(max_aw!=5||max_cmd_wait!=5)$fatal(1,"AW/CMD peak count");
 awready=1;tick();awvalid=0;cmd_valid=0;repeat(4)tick();
 if(max_first_w!=4||stage!=2)$fatal(1,"first W service count");
 wready=1;tick();wready=0;repeat(3)tick();
 if(max_w_gap!=3)$fatal(1,"W inter-beat gap");
 wready=1;wlast=1;tick();wready=0;
 arvalid=1;arready=1;tick();arvalid=0;repeat(6)tick();
 if(max_first_r!=6||stage!=4)$fatal(1,"first R service count");
 rvalid=1;tick();rvalid=0;repeat(2)tick();
 if(max_r_gap!=2)$fatal(1,"R inter-beat gap");
 rvalid=1;rlast=1;tick();rvalid=0;tick();
 if(stage!=0)$fatal(1,"service did not retire");
 arvalid=1;arready=1;rvalid=1;rlast=1;tick();
 arvalid=0;rvalid=0;#0.1;
 if(stage!=0)$fatal(1,"ZERO_LATENCY_SINGLE_R_NOT_RETIRED");
 arvalid=0;rvalid=0;tick();
 arvalid=1;arready=1;rvalid=1;rlast=0;tick();
 if(!dut.seen_r)$fatal(1,"same-edge first burst beat was not recorded");
 arvalid=0;rvalid=0;repeat(4)tick();
 if(max_r_gap!=4||max_first_r!=6)$fatal(1,"same-edge burst gap misclassified");
 rvalid=1;rlast=1;tick();rvalid=0;tick();
 rst_n=0;tick();if({max_aw,max_first_w,max_w_gap,max_first_r,max_r_gap,max_cmd_wait}!=0)$fatal(1,"common reset peaks");
 $display("PASS NATIVE_SERVICE exact AW5 CMD5 firstW4 Wgap3 firstR6 Rgap2, same-edge AR/R single/burst, inter-beat gap4 and common reset");$finish;
 end
endmodule
