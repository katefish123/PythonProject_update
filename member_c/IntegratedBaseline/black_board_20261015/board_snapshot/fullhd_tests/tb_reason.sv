`timescale 1ns/1ps
module tb_reason;
 reg clk=0,rst=0,start=0,rsp=0;always #5 clk=~clk;
 wire mv,busy,done,error,wv,gv;wire[23:0]ma,wa,wr;wire[31:0]cycles,pixels;wire[3:0]reason;
 frame_processor #(.SRC_W(8),.SRC_H(8),.OUT_W(8),.OUT_H(8),.MIN_PIXELS(4),.MAX_PIXELS(20),.MAX_SPAN(4)) dut(
 .clk(clk),.rst_n(rst),.start(start),.nearest(1'b0),.busy(busy),.done(done),.error(error),
 .mem_valid(mv),.mem_ready(1'b1),.mem_addr(ma),.mem_rsp_valid(rsp),.mem_rgb(24'd0),
 .write_valid(wv),.write_ready(1'b1),.write_addr(wa),.write_rgb(wr),.cycles(cycles),.completed_pixels(pixels),.geometry_valid(gv),.failure_reason(reason));
 always @(posedge clk)rsp<=rst&&mv;
 reg test_passed=0;
 initial begin #30;rst=1;@(negedge clk);start=1;@(negedge clk);start=0;
 repeat(2000)begin @(negedge clk);if(error)begin
 if(reason!=3)$fatal(1,"missing markers misclassified: %d",reason);
 if(done||pixels!=0)$fatal(1,"rejected frame published output");
 test_passed=1;$display("MARKER_REJECTION_REASON_PASS");$finish;end end $fatal(1,"no rejection");end
endmodule
