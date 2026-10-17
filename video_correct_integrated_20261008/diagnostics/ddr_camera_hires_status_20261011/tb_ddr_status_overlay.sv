`timescale 1ns/1ps
module tb_ddr_status_overlay;
 reg clk=0,reset_n=0,hs=0,vs=0,de=0;
 reg [23:0] rgb=0;
 reg [511:0] status_word=0;
 wire out_hs,out_vs,out_de,request;
 wire [23:0] out_rgb;
 reg test_passed=0;
 always #5 clk=~clk;
 ddr_status_overlay #(.CELL_W(2),.CELL_H(1),.STATUS_Y(3)) dut(
  .clk(clk),.reset_n(reset_n),.in_hs(hs),.in_vs(vs),.in_de(de),.in_rgb(rgb),
  .status_word(status_word),.snapshot_request(request),.out_hs(out_hs),.out_vs(out_vs),.out_de(out_de),.out_rgb(out_rgb));
 task frame(input [511:0] word);
  integer x,y,bit_number;
  reg [23:0] expected;
  begin
   @(negedge clk);de=0;vs=1;status_word=word;
   @(posedge clk);#1;
   if(!out_vs||!request)$fatal(1,"VS/request launch alignment");
   @(negedge clk);vs=0;
   for(y=0;y<36;y=y+1)begin
    for(x=0;x<32;x=x+1)begin
     @(negedge clk);de=1;rgb=24'h400000+y*256+x;
     if(y==1&&x==2)status_word=~word; // Must affect the next frame only.
     if(y>=3&&y<35)begin bit_number=511-(y-3)*16-x/2;expected=word[bit_number]?24'h00b000:24'hb00000;end
     else expected=rgb;
     @(posedge clk);#1;
     if(!out_de||out_vs!==vs||out_hs!==hs||out_rgb!==expected)$fatal(1,"pixel/timing mismatch %0d,%0d got=%h expected=%h",x,y,out_rgb,expected);
    end
    @(negedge clk);de=0;
    @(posedge clk);#1;if(out_de||out_rgb!=0)$fatal(1,"blanking mismatch");
   end
  end
 endtask
 initial begin
  repeat(3)@(negedge clk);reset_n=1;
  frame({16{32'hd205a5c3}});frame({16{32'h2dfa5a3c}});
  @(negedge clk);reset_n=0;
  #1;if(out_de||out_rgb||request)$fatal(1,"asynchronous reset did not cancel output");
  test_passed=1;$display("DDR_STATUS_OVERLAY_PASS all512bits=1 camera_pixels=1 frame_latched=1 timing_aligned=1 reset=1");$finish;
 end
 initial begin #100000;$fatal(1,"overlay timeout");end
endmodule
