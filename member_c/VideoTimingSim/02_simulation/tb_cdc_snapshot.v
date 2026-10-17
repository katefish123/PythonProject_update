`timescale 1ns/1ps
module tb_cdc_snapshot;
reg sc=0,dc=0,rst=0,request=0,run_source=1;
reg [7:0] count=0;
wire [31:0] data;wire valid,busy;
integer n,received=0;reg test_failed=0;integer test_passed=0;
always #3.37 if(run_source)sc=~sc;
always #5.11 dc=~dc;
always @(posedge sc)count<=count+1;
cdc_snapshot dut(sc,rst,{count,~count,count,~count},dc,rst,request,data,valid,busy);
always @(posedge dc)if(valid)begin
 received=received+1;
 if(data[31:24]!=data[15:8] || data[23:16]!=data[7:0] || data[31:24]!=~data[23:16])begin test_failed=1;$display("FAIL_TORN_SNAPSHOT %h",data);$finish;end
end
initial begin
 #31;rst=1;
 for(n=0;n<50;n=n+1)begin
  @(negedge dc);request=1;@(negedge dc);request=0;
  wait(valid);repeat(3)@(negedge dc);
 end
 #20;if(received!=50)begin test_failed=1;$display("FAIL_SNAPSHOT_COUNT");$finish;end
 rst=0;#20;if(busy || valid || data!=0)begin test_failed=1;$display("FAIL_SNAPSHOT_RESET");$finish;end
 test_passed=1;$display("PASS_COHERENT_SNAPSHOT 50");$finish;
end
initial begin #100000;test_failed=1;$display("FAIL_SNAPSHOT_TIMEOUT");$finish;end
endmodule
