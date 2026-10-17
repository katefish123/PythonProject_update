`timescale 1ns/1ps
module tb_q30_alu;
 reg clk=0,rst_n=0,start=0;always #5 clk=~clk;
 reg[1:0]op;reg signed[63:0]a,b;
 wire ready,done,error;wire signed[63:0]value;
 q30_alu dut(.*);
 task run(input[1:0]o,input signed[63:0]x,y,want,input bit bad);
 begin @(negedge clk);op=o;a=x;b=y;start=1;@(negedge clk);start=0;
 wait(done);if(error!==bad||(!bad&&value!==want))$fatal(1,"Q30_ALU op%0d actual=%0d wanted=%0d bad=%b",o,value,want,error);
 @(negedge clk);end endtask
 initial begin
 repeat(3)@(negedge clk);rst_n=1;
 run(0,64'sh7fffffffffffffff,1,0,1);
 run(0,-17,8,-9,0);
 run(1,1,64'sd536870912,0,0); // +.5 LSB ties even
 run(1,3,64'sd536870912,2,0);
 run(1,-3,64'sd536870912,-2,0);
 run(1,64'sh7fffffffffffffff,64'sh7fffffffffffffff,0,1);
 run(2,3,64'sd2147483648,2,0); // quotient1.5 ->2
 run(2,-3,64'sd2147483648,-2,0);
 run(2,1,64'sd2147483648,0,0);
 run(2,1073741824,0,0,1);
 run(2,64'sh7fffffffffffffff,1,0,1);
 run(2,64'sh8000000000000000,1073741824,64'sh8000000000000000,0);
 @(negedge clk);op=2;a=123;b=456;start=1;@(negedge clk);start=0;
 repeat(5)@(negedge clk);rst_n=0;@(negedge clk);rst_n=1;
 repeat(140)@(negedge clk);if(done||!ready)$fatal(1,"ALU reset left stale operation");
 $display("PASS Q30_ALU signed nearest-even, overflow, zero divisor, in-flight reset");$finish;
 end
 initial begin #50000;$fatal(1,"ALU timeout");end
endmodule
