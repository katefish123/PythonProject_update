`timescale 1ns/1ps
module tb_input_monitor;
 reg clk=0,rst=0,vs=0,de=0;always #5 clk=~clk;
 wire[159:0]q;
 input_geometry_monitor dut(clk,rst,vs,de,q);
 task cycles(input integer n); repeat(n)@(negedge clk);endtask
 task frame(input integer w,h,blank);
 integer x,y;begin
 vs=1;cycles(4);vs=0;cycles(blank);
 for(y=0;y<h;y=y+1)begin de=1;cycles(w);de=0;cycles(5);end
 cycles(blank);
 end endtask
 initial begin cycles(3);rst=1;cycles(3);
 frame(1920,1080,20);frame(1920,1080,20);cycles(3);
 if(q[15:0]!=1920||q[31:16]!=1080||q[63:32]!=2073600||q[79:64]!=1920||q[95:80]!=1920)$fatal(1,"FULLHD_GEOMETRY %h",q);
 frame(1920,1080,200);cycles(3);
 if(q[15:0]!=1920||q[31:16]!=1080||q[63:32]!=2073600)$fatal(1,"BLANKING_CHANGED_GEOMETRY");
 frame(1280,720,20);frame(1280,720,20);cycles(3);
 if(q[15:0]!=1280||q[31:16]!=720||q[63:32]!=921600)$fatal(1,"WRONG_SIZE_NOT_OBSERVED %h",q);
 $display("PASS INPUT_MONITOR_FULLHD_AND_WRONG_SIZE");$finish;end
 initial begin #100000000;$fatal(1,"TIMEOUT");end
endmodule
