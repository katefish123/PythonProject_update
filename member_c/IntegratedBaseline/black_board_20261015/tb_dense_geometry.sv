`timescale 1ns/1ps
module tb_dense_geometry;
 reg rx=0,proc=0;always #3.367 rx=~rx;always #18.519 proc=~proc;
 reg rst=0,pv=0,first=0,last=0,done=0;reg [23:0] rgb=24'h808080;
 wire mt,mid,mb,good;wire[95:0]corners;reg test_passed=0;
 capture_geometry #(.SRC_W(1920),.SRC_H(1080),.MIN_PIXELS(64),.MAX_PIXELS(16384),.MAX_SPAN(256),
  .P0_XMIN(580),.P0_XMAX(681),.P0_YMIN(86),.P0_YMAX(187),
  .P1_XMIN(1410),.P1_XMAX(1511),.P1_YMIN(174),.P1_YMAX(275),
  .P2_XMIN(1480),.P2_XMAX(1581),.P2_YMIN(920),.P2_YMAX(1021),
  .P3_XMIN(226),.P3_XMAX(327),.P3_YMIN(886),.P3_YMAX(987)) dut(
  .rx_clk(rx),.rx_rst_n(rst),.proc_clk(proc),.proc_rst_n(rst),
  .sample_valid(pv),.sample_first(first),.sample_last(last),.sample_rgb(rgb),
  .sample_token(1'b1),.sample_bank(1'b1),.rx_complete_toggle(done),
  .metadata_toggle(mt),.metadata_token(mid),.metadata_bank(mb),.metadata_ok(good),.metadata_corners(corners));
 always @(negedge rx)if(rst&&dut.rx_overflow)$fatal(1,"dense full-HD ROI FIFO overflow");
 initial begin
  repeat(10)@(negedge proc);rst=1;repeat(10)@(negedge proc);
  for(integer y=0;y<1080;y=y+1)begin
   for(integer x=0;x<1920;x=x+1)begin
    @(negedge rx);pv=1;first=(x==0&&y==0);last=(x==1919&&y==1079);
    rgb=((x>=580&&x<=681&&y>=86&&y<=187)||(x>=1410&&x<=1511&&y>=174&&y<=275)||
      (x>=1480&&x<=1581&&y>=920&&y<=1021)||(x>=226&&x<=327&&y>=886&&y<=987))?24'd0:24'h808080;
   end
   @(negedge rx);pv=0;first=0;last=0;repeat(279)@(negedge rx);
  end
  done=1;wait(mt==1);@(negedge proc);
  if(!good||!mid||!mb||corners!=={12'd631,12'd137,12'd1461,12'd225,12'd1531,12'd971,12'd277,12'd937})
   $fatal(1,"dense full-HD ROI centroid/identity mismatch %h",corners);
  test_passed=1;$display("DENSE_GEOMETRY_PASS fullhd_2073600_pixels dense_41616_ROI_samples no_overflow exact_centroids");$finish;
 end
 initial begin #30000000;$fatal(1,"dense full-HD geometry timeout");end
endmodule
