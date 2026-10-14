`timescale 1ns/1ps
module tb_black_roi_scan;
 reg clk=0,rst_n=0,start=0,nearest=0;
 always #5 clk=~clk;
 wire [1:0] busy,done,error,mem_valid,mem_ready,write_valid,write_ready,geometry_valid;
 wire [23:0] mem_addr[0:1],write_addr[0:1],write_rgb[0:1];
 wire [31:0] cycles[0:1],completed_pixels[0:1];
 reg [1:0] mem_rsp_valid=0;
 reg [23:0] mem_rgb[0:1];
 reg [23:0] source0[0:3071],source1[0:3071],expected0[0:767],expected1[0:767];
 reg [1:0] pending=0,done_seen=0;
 integer delay_left[0:1],saved_addr[0:1],scan_reads[0:1],writes[0:1],frame_starts[0:1],frame_ends[0:1];
 integer cycle_no=0,variant=0;
 reg test_passed=0;
 genvar g;
 generate for(g=0;g<2;g=g+1)begin: engines
  assign mem_ready[g]=!pending[g]&&(cycle_no%7!=g);
  assign write_ready[g]=(cycle_no%47<23+g);
  frame_processor #(.SRC_W(64),.SRC_H(48),.OUT_W(32),.OUT_H(24),.ROI_SCAN_ONLY(g),
   .P0_XMIN(5),.P0_XMAX(15),.P0_YMIN(3),.P0_YMAX(13),
   .P1_XMIN(47),.P1_XMAX(57),.P1_YMIN(8),.P1_YMAX(18),
   .P2_XMIN(51),.P2_XMAX(61),.P2_YMIN(35),.P2_YMAX(45),
   .P3_XMIN(2),.P3_XMAX(12),.P3_YMIN(33),.P3_YMAX(43)) dut(
    .clk(clk),.rst_n(rst_n),.start(start),.nearest(nearest),.busy(busy[g]),.done(done[g]),.error(error[g]),
    .mem_valid(mem_valid[g]),.mem_ready(mem_ready[g]),.mem_addr(mem_addr[g]),
    .mem_rsp_valid(mem_rsp_valid[g]),.mem_rgb(mem_rgb[g]),.write_valid(write_valid[g]),
    .write_ready(write_ready[g]),.write_addr(write_addr[g]),.write_rgb(write_rgb[g]),
    .cycles(cycles[g]),.completed_pixels(completed_pixels[g]),.geometry_valid(geometry_valid[g]));
  always @(posedge clk)begin
   mem_rsp_valid[g]<=0;
   if(!rst_n)begin pending[g]<=0;delay_left[g]<=0;scan_reads[g]=0;writes[g]=0;frame_starts[g]=0;frame_ends[g]=0;end
   else begin
    if(dut.src_valid&&dut.scan_first)frame_starts[g]=frame_starts[g]+1;
    if(dut.src_valid&&dut.scan_last)frame_ends[g]=frame_ends[g]+1;
    if(mem_valid[g]&&mem_ready[g])begin
     if(pending[g]||mem_addr[g]>=3072)$fatal(1,"invalid/overlapping source read engine=%0d",g);
     pending[g]<=1;saved_addr[g]<=mem_addr[g];delay_left[g]<=1+(cycle_no%3);
     if(dut.state==1)scan_reads[g]=scan_reads[g]+1;
    end else if(pending[g])begin
     if(delay_left[g]>0)delay_left[g]<=delay_left[g]-1;
     else begin
      mem_rgb[g]<=variant==0?source0[saved_addr[g]]:source1[saved_addr[g]];
      mem_rsp_valid[g]<=1;pending[g]<=0;
     end
    end
    if(write_valid[g]&&write_ready[g])begin
     if(write_addr[g]!==writes[g])$fatal(1,"write order engine=%0d",g);
     if(write_rgb[g]!==(variant==0?expected0[writes[g]]:expected1[writes[g]]))$fatal(1,"RGB mismatch engine=%0d pixel=%0d",g,writes[g]);
     writes[g]=writes[g]+1;
    end
    if(done[g])done_seen[g]<=1;
    if(error[g])$fatal(1,"unexpected processor error engine=%0d",g);
   end
  end
 end endgenerate
 always @(posedge clk)cycle_no=cycle_no+1;
 initial begin
  $readmemh("roi_source0.hex",source0);$readmemh("roi_source1.hex",source1);
  $readmemh("roi_expected0.hex",expected0);$readmemh("roi_expected1.hex",expected1);
  for(integer n=0;n<2;n=n+1)begin
   @(negedge clk);rst_n=0;done_seen=0;variant=n;nearest=n;repeat(4)@(negedge clk);rst_n=1;
   @(negedge clk);start=1;@(negedge clk);start=0;
   wait(done_seen==2'b11);@(negedge clk);
   for(integer i=0;i<2;i=i+1)begin
    if(writes[i]!=768||completed_pixels[i]!=768||frame_starts[i]!=1||frame_ends[i]!=1)$fatal(1,"frame accounting engine=%0d",i);
   end
   if(scan_reads[0]!=3072||scan_reads[1]!=484)$fatal(1,"sparse scan area mismatch full=%0d sparse=%0d",scan_reads[0],scan_reads[1]);
   if(cycles[1]>=cycles[0])$fatal(1,"sparse scan did not reduce total cycles");
   $display("ROI_EQUIVALENCE frame=%0d full_cycles=%0d sparse_cycles=%0d pixels=768",n,cycles[0],cycles[1]);
  end
  $display("BLACK_ROI_SCAN_PASS frames=2 pixels=3072 full_scan=3072 sparse_scan=484");
  test_passed=1;$finish;
 end
 initial begin #5000000;$fatal(1,"ROI scan timeout");end
endmodule
