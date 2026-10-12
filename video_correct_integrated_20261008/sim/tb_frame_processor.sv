`timescale 1ns/1ps
module tb_frame_processor;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,start=0,nearest=0;
 wire busy,done,error,rv,wv,geom;
 wire [23:0] ra,wa,wd;
 wire [31:0] cycles,completed;
 reg response=0;reg [23:0] data=0;
 reg [23:0] memory[0:3071],expected[0:767];
 integer tick=0,left=0,read_address=0,reads=0,writes=0,phase=0;
 integer max_latency=0,stalled_reads=0,stalled_writes=0;
 wire ready=(left==0)&&(tick%5!=1)&&(tick%7!=3);
 wire wr_ready=(tick%7<4);
 reg test_passed=0;
 frame_processor #(.TIMEOUT_CYCLES(10000)) dut(
  .clk(clk),.rst_n(rst_n),.start(start),.nearest(nearest),.busy(busy),.done(done),.error(error),
  .mem_valid(rv),.mem_ready(ready),.mem_addr(ra),.mem_rsp_valid(response),.mem_rgb(data),
  .write_valid(wv),.write_ready(wr_ready),.write_addr(wa),.write_rgb(wd),
  .cycles(cycles),.completed_pixels(completed),.geometry_valid(geom));
 always @(posedge clk)begin
  if(!rst_n)begin tick<=0;left<=0;response<=0;data<=0;end
  else begin
   tick<=tick+1;response<=0;
   if(rv&&!ready)stalled_reads=stalled_reads+1;
   if(wv&&!wr_ready)stalled_writes=stalled_writes+1;
   if(rv&&ready)begin
    if(ra>=3072)$fatal(1,"source OOB %0d",ra);
    left<=1+(tick%7);read_address<=ra;reads=reads+1;
    if(1+(tick%7)>max_latency)max_latency=1+(tick%7);
   end else if(left>0)begin
    left<=left-1;
    if(left==1)begin response<=1;data<=memory[read_address];end
   end
   if(wv&&wr_ready)begin
    if(writes>=768||wa!==24'(writes))$fatal(1,"write address phase=%0d count=%0d addr=%0d",phase,writes,wa);
    if(wd!==expected[writes])$fatal(1,"pixel mismatch phase=%0d i=%0d got=%h ref=%h",phase,writes,wd,expected[writes]);
    writes=writes+1;
   end
  end
 end
 task run_frame(input integer scene,input integer nn);
  begin
   phase=scene;writes=0;reads=0;
   if(scene==0)begin $readmemh("vendor/b/vectors/source0.hex",memory);$readmemh("vendor/b/vectors/expected0.hex",expected);end
   else begin $readmemh("vendor/b/vectors/source1.hex",memory);$readmemh("vendor/b/vectors/expected1.hex",expected);end
   @(negedge clk);nearest=nn;start=1;@(negedge clk);start=0;
   wait(done||error);@(negedge clk);
   if(error||writes!=768||completed!=768)$fatal(1,"frame failed scene=%0d writes=%0d",scene,writes);
   if(reads!=3072+768*(nn?1:4))$fatal(1,"unexpected source access count %0d",reads);
   $display("FRAME_PASS scene=%0d nearest=%0d pixels=%0d reads=%0d cycles=%0d",scene,nn,writes,reads,cycles);
   repeat(5)@(negedge clk);
  end
 endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  run_frame(0,0);run_frame(1,1);
  // A rejected new source must never publish stale geometry as a new frame.
  $readmemh("vendor/b/vectors/source2.hex",memory);writes=0;
  @(negedge clk);start=1;@(negedge clk);start=0;
  wait(done||error);@(negedge clk);
  if(!error||writes!=0)$fatal(1,"rejected source published a result");
  $display("REJECT_PASS no partial destination published");
  // Cancel an accepted read; the memory owner clears its response pipeline too.
  $readmemh("vendor/b/vectors/source0.hex",memory);
  @(negedge clk);start=1;@(negedge clk);start=0;
  wait(left>1);@(negedge clk);rst_n=0;
  repeat(3)@(negedge clk);rst_n=1;
  repeat(40)begin @(negedge clk);if(wv||rv||done)$fatal(1,"stale transaction after reset");end
  run_frame(0,0);
  if(max_latency<7||stalled_reads==0||stalled_writes==0)$fatal(1,"missing stall coverage");
  test_passed=1;
  $display("FRAME_PROCESSOR_PASS variable_latency=1..7 read_stalls=%0d write_stalls=%0d reset_recovery=yes",stalled_reads,stalled_writes);
  $finish;
 end
 initial begin #5000000;$fatal(1,"integration timeout");end
endmodule
