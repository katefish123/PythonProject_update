`timescale 1ns/1ps
module tb_hdmi_source_stream;
parameter W=8,H=4;
reg clk=0,rst_n=0,link_valid=0,vs=0,de=0;
reg [23:0] rgb=0;
always #5 clk=~clk;
wire valid,sof,eof,abort_frame;
wire [11:0] x,y;
wire [23:0] pixel;
integer received=0,starts=0,ends=0,aborts=0,test_passed=0;
reg checking=0;
hdmi_source_stream #(.WIDTH(W),.HEIGHT(H)) dut(
 .clk(clk),.rst_n(rst_n),.link_valid(link_valid),.vs(vs),.de(de),.rgb(rgb),
 .src_valid(valid),.src_frame_start(sof),.src_frame_end(eof),
 .src_x(x),.src_y(y),.src_rgb(pixel),.frame_abort(abort_frame));
always @(negedge clk) begin
 if(abort_frame) aborts=aborts+1;
 if(sof) starts=starts+1;
 if(eof) ends=ends+1;
 if(valid && checking) begin
  if(x!==received%W || y!==received/W || pixel!==24'h100000+received ||
     sof!==(received==0) || eof!==(received==W*H-1)) begin
   $display("FAIL_STREAM index=%0d xy=%0d,%0d rgb=%h sof=%b eof=%b",received,x,y,pixel,sof,eof); $finish;
  end
  received=received+1;
 end
end
task tick(input d,input v,input [23:0] p);
 begin @(negedge clk); de=d;vs=v;rgb=p; @(posedge clk); #1; end
endtask
task boundary;
 begin tick(0,1,0);tick(0,0,0); end
endtask
task good_frame;
 integer row,col;
 begin
  received=0;starts=0;ends=0;checking=1;boundary;
  for(row=0;row<H;row=row+1) begin
   for(col=0;col<W;col=col+1) tick(1,0,24'h100000+row*W+col);
   tick(0,0,0);tick(0,0,0);
  end
  tick(0,0,0);
  if(received!=W*H || starts!=1 || ends!=1) begin
   $display("FAIL_STREAM_COUNT received=%0d starts=%0d ends=%0d",received,starts,ends);$finish;
  end
  checking=0;
 end
endtask
integer a;
initial begin
 tick(0,0,0);rst_n=1;link_valid=1;
 // A partial frame after reset must not reach B before a frame boundary.
 tick(1,0,24'hbad);tick(0,0,0);
 if(valid || starts || ends)begin $display("FAIL_STARTUP_PARTIAL");$finish;end
 good_frame;good_frame;
 a=aborts;boundary;tick(1,0,1);tick(1,0,2);tick(0,0,0);tick(0,0,0);
 if(aborts!=a+1)begin $display("FAIL_SHORT_LINE_ABORT");$finish;end
 good_frame;
 boundary;tick(1,0,1);link_valid=0;tick(1,0,2);tick(0,0,0);
 if(valid)begin $display("FAIL_LINK_LOSS_VALID");$finish;end
 link_valid=1;tick(1,0,3);tick(0,0,0);
 if(valid)begin $display("FAIL_RECONNECT_PARTIAL");$finish;end
 good_frame;
 boundary;tick(1,0,1);rst_n=0;tick(1,0,2);rst_n=1;
 tick(1,0,3);tick(0,0,0);
 if(valid)begin $display("FAIL_RESET_PARTIAL");$finish;end
 good_frame;
 a=aborts;boundary;tick(1,0,1);boundary;tick(0,0,0);
 if(aborts!=a+1)begin $display("FAIL_EARLY_BOUNDARY");$finish;end
 good_frame;
 test_passed=1;$display("PASS_SOURCE_STREAM W=%0d H=%0d",W,H);$finish;
end
initial begin #200000000; $display("FAIL_STREAM_TIMEOUT");$finish;end
endmodule
