`timescale 1ns/1ps
module tb_board_frame;
 localparam SRC_W=320,SRC_H=180,OUT_W=160,OUT_H=226;
 reg clk=0,rst_n=0,start=0,nearest=0;
 always #18.518518 clk=~clk;
 wire busy,done,error,mem_valid,write_valid,geometry_valid;
 wire [23:0] mem_addr,write_addr,write_rgb;
 wire [31:0] cycles,completed_pixels;
 reg mem_rsp_valid=0;
 reg [23:0] mem_rgb=0;
 reg [23:0] source[0:SRC_W*SRC_H-1];
 reg [23:0] expected[0:OUT_W*OUT_H-1];
 integer reads=0,writes=0,expected_reads=0,k;
 real seconds_27mhz;
 reg test_passed=0;
 frame_processor #(.SRC_W(SRC_W),.SRC_H(SRC_H),.OUT_W(OUT_W),.OUT_H(OUT_H),
  .MIN_PIXELS(16),.MAX_PIXELS(4096),.MAX_SPAN(128),.TIMEOUT_CYCLES(5000000)) dut(
  .clk(clk),.rst_n(rst_n),.start(start),.nearest(nearest),.busy(busy),.done(done),.error(error),
  .mem_valid(mem_valid),.mem_ready(1'b1),.mem_addr(mem_addr),.mem_rsp_valid(mem_rsp_valid),.mem_rgb(mem_rgb),
  .write_valid(write_valid),.write_ready(1'b1),.write_addr(write_addr),.write_rgb(write_rgb),
  .cycles(cycles),.completed_pixels(completed_pixels),.geometry_valid(geometry_valid));
 always @(posedge clk)begin
  if(!rst_n)begin mem_rsp_valid<=0;mem_rgb<=0;end
  else begin
   mem_rsp_valid<=mem_valid;
   if(mem_valid)begin
    if(mem_addr>=SRC_W*SRC_H)$fatal(1,"source read OOB addr=%0d",mem_addr);
    mem_rgb<=source[mem_addr];reads=reads+1;
   end
   if(write_valid)begin
    if(writes>=OUT_W*OUT_H)$fatal(1,"too many output writes");
    if(write_addr!==24'(writes))$fatal(1,"write order mismatch index=%0d addr=%0d",writes,write_addr);
    if(write_rgb!==expected[writes])$fatal(1,"fixed golden mismatch pixel=%0d got=%h expected=%h",writes,write_rgb,expected[writes]);
    writes=writes+1;
   end
  end
 end
 initial begin
  $readmemh("results/board_fixture/source_320x180.hex",source);
  $readmemh("results/board_fixture/expected_160x226.hex",expected);
  k=$fopen("results/board_fixture/expected_reads.txt","r");
  if(!k)$fatal(1,"cannot open golden read-count fixture");
  if($fscanf(k,"%d",expected_reads)!=1)$fatal(1,"cannot read golden read count");
  $fclose(k);
  repeat(5)@(negedge clk);rst_n=1;
  @(negedge clk);start=1;@(negedge clk);start=0;
  wait(done||error);@(negedge clk);
  if(error)$fatal(1,"frame_processor rejected board fixture");
  if(writes!=OUT_W*OUT_H || completed_pixels!=OUT_W*OUT_H)
   $fatal(1,"pixel count mismatch writes=%0d completed=%0d",writes,completed_pixels);
  if(reads!=expected_reads)$fatal(1,"read count mismatch reads=%0d expected=%0d",reads,expected_reads);
  if(!geometry_valid)$fatal(1,"geometry never became valid");
  seconds_27mhz=cycles/27000000.0;
  $display("BOARD_FRAME_PASS checked_pixels=%0d",writes);
  $display("BOARD_COUNTS cycles=%0d reads=%0d writes=%0d",cycles,reads,writes);
  $display("THEORETICAL_27MHZ_ALGORITHM_SECONDS=%.9f (cycle_count / 27000000; not hardware FPS)",seconds_27mhz);
  test_passed=1;$finish;
 end
 initial begin #500000000;$fatal(1,"board frame simulation timeout");end
endmodule
