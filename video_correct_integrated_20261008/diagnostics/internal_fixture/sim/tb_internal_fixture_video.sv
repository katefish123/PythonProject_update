`timescale 1ns/1ps
`default_nettype none
module tb_internal_fixture_video;
 reg clk=0,reset_n=0;
 wire vsync,hsync,de; wire [23:0] rgb; wire [11:0] raster_x,raster_y;
 reg [23:0] expected[0:307199];
 integer checked=0, line_hits=0, frame_lines=0;
 reg [479:0] seen_rows;
 internal_fixture_video dut(.clk(clk),.reset_n(reset_n),.vsync(vsync),.hsync(hsync),.de(de),.rgb(rgb),.raster_x(raster_x),.raster_y(raster_y));
 always #18.518 clk=~clk;
 integer sy,sx,idx,first_r;
 initial begin
  $readmemh("diagnostics/internal_fixture/fixture/source_640x480.hex",expected);
  seen_rows={480{1'b0}};
  repeat(8) @(posedge clk); reset_n<=1;
  while(checked<691200) begin
   @(negedge clk);
   if(de) begin
    sy=(raster_y*4+8)/9; if(sy>479)sy=479;
    sx=raster_x/3;
    // Check every coordinate selected by the x/y floor/ceil sampler.
    if((raster_x%3)==0) begin
     idx=sy*640+sx;
     if(rgb!==expected[idx]) begin
      $display("MISMATCH x=%0d y=%0d src=(%0d,%0d) got=%06x want=%06x",raster_x,raster_y,sx,sy,rgb,expected[idx]);
      $fatal(1,"procedural raster differs from fixture golden");
     end
     checked=checked+1;
     if(raster_y<1080) seen_rows[sy]=1'b1;
    end
   end
  end
  for(integer i=0;i<480;i=i+1) if(seen_rows[i]) line_hits=line_hits+1;
  if(checked!=691200 || line_hits!=480) $fatal(1,"coverage mismatch checked=%0d rows=%0d",checked,line_hits);
  $display("FIXTURE_TB_CHECKED_PIXELS=%0d ROWS=%0d",checked,line_hits);
  $display("test_passed=1"); $display("PASS: internal fixture raster matches source golden");
  $finish;
 end
 initial begin #120000000; $fatal(1,"timeout"); end
endmodule
`default_nettype wire


