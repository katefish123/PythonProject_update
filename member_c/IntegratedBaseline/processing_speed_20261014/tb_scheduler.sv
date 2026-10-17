`timescale 1ns/1ps
module tb_scheduler;
 localparam SW=16,SH=12,OW=24,OH=20,N=OW*OH;
 reg clk=0,rst_n=0,start=0,nearest=0;always #5 clk=~clk;
 wire busy,done,error,mv,wrv,geometry;wire [23:0] ma,wa,wrgb;wire [31:0] cycles,pixels;
 reg mrsp=0;reg [23:0] mrgb=0;reg pending=0;reg [23:0] held_addr=0;
 integer delay_count=0,tick=0,writes=0,run_no=0;
 reg [31:0] rng=32'h842193ab;reg test_passed=0;
 wire ready=rst_n&&!pending&&(rng[2:0]!=0);
 wire write_ready=rst_n&&(tick%311>=180);
 frame_processor #(.SRC_W(SW),.SRC_H(SH),.OUT_W(OW),.OUT_H(OH),.FIXED_IDENTITY(1)) dut(
  .clk(clk),.rst_n(rst_n),.start(start),.nearest(nearest),.busy(busy),.done(done),.error(error),
  .mem_valid(mv),.mem_ready(ready),.mem_addr(ma),.mem_rsp_valid(mrsp),.mem_rgb(mrgb),
  .write_valid(wrv),.write_ready(write_ready),.write_addr(wa),.write_rgb(wrgb),
  .cycles(cycles),.completed_pixels(pixels),.geometry_valid(geometry));
 function [23:0] color(input integer addr);color=24'h403020+addr*257;endfunction
 reg held_write=0;reg [47:0] stalled_write=0;
 always @(posedge clk)begin
  tick<=tick+1;rng<={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};mrsp<=0;
  if(!rst_n)begin pending<=0;writes=0;held_write<=0;end
  else begin
   if(error)$fatal(1,"scheduler error during run %0d",run_no);
   if(mv&&ready)begin
    if(ma>=SW*SH)$fatal(1,"out-of-bounds request not suppressed");
    held_addr<=ma;pending<=1;delay_count<=1+rng[6:3];
   end
   if(pending)begin
    if(delay_count!=0)delay_count<=delay_count-1;
    else begin pending<=0;mrgb<=color(held_addr);mrsp<=1;end
   end
   if(held_write&&{wa,wrgb}!==stalled_write)$fatal(1,"result changed while backpressured");
   held_write<=wrv&&!write_ready;stalled_write<={wa,wrgb};
   if(wrv&&write_ready)begin
    if(wa!==writes)$fatal(1,"reordered output address %0d expected %0d",wa,writes);
    if(wrgb!==((writes%OW<SW&&writes/OW<SH)?color((writes/OW)*SW+writes%OW):24'd0))
     $fatal(1,"incorrect RGB or outside black pixel addr=%0d",writes);
    writes=writes+1;
   end
  end
 end
 task begin_run(input integer mode);
  begin
   @(negedge clk);rst_n=0;start=0;nearest=mode;
   repeat(6)@(negedge clk);rst_n=1;repeat(3)@(negedge clk);start=1;
   @(negedge clk);start=0;
  end
 endtask
 initial begin
  begin_run(0);wait(writes==20);begin_run(0);run_no=1;
  wait(done);@(negedge clk);
  if(writes!=N||pixels!=N)$fatal(1,"incomplete recovered bilinear frame");
  $display("SCHEDULER_CASE bilinear cycles=%0d pixels=%0d",cycles,writes);
  if(cycles>=37500)$fatal(1,"BILINEAR_SCHEDULER_TOO_SLOW cycles=%0d",cycles);
  begin_run(1);run_no=2;wait(done);@(negedge clk);
  if(writes!=N||pixels!=N)$fatal(1,"incomplete nearest frame");
  $display("SCHEDULER_CASE nearest cycles=%0d pixels=%0d",cycles,writes);
  if(cycles>=26900)$fatal(1,"NEAREST_SCHEDULER_TOO_SLOW cycles=%0d",cycles);
  test_passed=1;$display("SCHEDULER_BACKPRESSURE_RESET_PASS");$finish;
 end
 initial begin #20000000;$fatal(1,"scheduler timeout");end
endmodule
