`timescale 1ns/1ps
module tb_marker_config;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0;
 reg default_pv=0,default_fs=0,default_fe=0;
 reg [11:0] default_x=0,default_y=0;
 wire default_cv,default_reject,default_drop,default_busy;
 wire [11:0] dx0,dy0,dx1,dy1,dx2,dy2,dx3,dy3;
 marker_detector #(.SRC_W(65),.SRC_H(49),.MIN_PIXELS(1),.MAX_PIXELS(8)) odd_source(
  clk,rst_n,default_pv,default_fs,default_fe,default_x,default_y,24'h000000,
  default_cv,default_reject,default_drop,default_busy,dx0,dy0,dx1,dy1,dx2,dy2,dx3,dy3);
 reg custom_pv=0,custom_fs=0,custom_fe=0;
 reg [11:0] custom_x=0,custom_y=0;
 reg [23:0] custom_rgb=24'h202020;
 wire custom_cv,custom_reject,custom_drop,custom_busy;
 wire [11:0] cx0,cy0,cx1,cy1,cx2,cy2,cx3,cy3;
 marker_detector #(.SRC_W(65),.SRC_H(49),.MIN_PIXELS(4),.MAX_PIXELS(4),.MAX_SPAN(1),
  .BLACK_RMIN(32),.BLACK_GMIN(32),.BLACK_BMIN(32),
  .P0_XMIN(2),.P0_XMAX(3),.P0_YMIN(2),.P0_YMAX(3),
  .P1_XMIN(60),.P1_XMAX(61),.P1_YMIN(2),.P1_YMAX(3),
  .P2_XMIN(60),.P2_XMAX(61),.P2_YMIN(43),.P2_YMAX(44),
  .P3_XMIN(2),.P3_XMAX(3),.P3_YMIN(43),.P3_YMAX(44)) custom_roi(
  clk,rst_n,custom_pv,custom_fs,custom_fe,custom_x,custom_y,custom_rgb,
  custom_cv,custom_reject,custom_drop,custom_busy,cx0,cy0,cx1,cy1,cx2,cy2,cx3,cy3);
 localparam INVALID_CASES=22;
 reg invalid_pv=0,invalid_fs=0,invalid_fe=0;
 reg [11:0] invalid_x=0,invalid_y=0;
 reg [23:0] invalid_rgb=24'hffffff;
 wire [INVALID_CASES-1:0] invalid_cv,invalid_reject,invalid_drop,invalid_busy;
 genvar n;
 generate for(n=0;n<INVALID_CASES;n=n+1)begin: bad_config
  // Cases 0..5 overlap each distinct pair only along an unoccupied edge
  // or point. Four black samples still hit exactly one ROI apiece, so the
  // configuration guard itself must reject even without an ambiguous pixel.
  localparam X0MIN=(n==6)?-1:(n==8)?3:1;
  localparam X0MAX=(n==7)?16:(n==0||n==1)?6:2;
  localparam Y0MIN=(n==9)?-1:(n==11)?3:1;
  localparam Y0MAX=(n==10)?16:(n==1||n==2)?6:2;
  localparam X1MIN=(n==0||n==4)?6:10;
  localparam Y1MAX=(n==3||n==4)?6:2;
  localparam X2MIN=(n==1||n==5)?6:10;
  localparam Y2MIN=(n==1||n==3)?6:10;
  localparam X3MAX=(n==4||n==5)?6:2;
  localparam Y3MIN=(n==2||n==4)?6:10;
  marker_detector #(.SRC_W((n==16)?4097:16),.SRC_H((n==17)?0:16),
   .MIN_PIXELS((n==18)?0:1),.MAX_PIXELS((n==19)?0:(n==21)?16777217:4),.MAX_SPAN((n==20)?-1:128),
   .BLACK_RMIN((n==12)?65:(n==13)?-1:0),
   .BLACK_GMAX((n==14)?256:64),.BLACK_BMAX((n==15)?-1:64),
   .P0_XMIN(X0MIN),.P0_XMAX(X0MAX),.P0_YMIN(Y0MIN),.P0_YMAX(Y0MAX),
   .P1_XMIN(X1MIN),.P1_XMAX(11),.P1_YMIN(1),.P1_YMAX(Y1MAX),
   .P2_XMIN(X2MIN),.P2_XMAX(11),.P2_YMIN(Y2MIN),.P2_YMAX(11),
   .P3_XMIN(1),.P3_XMAX(X3MAX),.P3_YMIN(Y3MIN),.P3_YMAX(11)) bad_dut(
   clk,rst_n,invalid_pv,invalid_fs,invalid_fe,invalid_x,invalid_y,invalid_rgb,
   invalid_cv[n],invalid_reject[n],invalid_drop[n],invalid_busy[n]);
 end endgenerate
 integer default_seen=0,custom_seen=0,custom_rejected=0,invalid_frames=0;
 reg [95:0] default_expected=0;
 reg test_passed=0;
 always @(posedge clk)begin
  #1;
  if(rst_n)begin
   if(default_reject||default_drop||custom_drop)$fatal(1,"valid ROI configuration rejected/dropped");
   if(default_cv)begin
    if({dx0,dy0,dx1,dy1,dx2,dy2,dx3,dy3}!==default_expected)$fatal(1,"odd-source corner/ROI boundary mismatch");
    default_seen=default_seen+1;
   end
   if(custom_cv)begin
    if({cx0,cy0,cx1,cy1,cx2,cy2,cx3,cy3}!=={12'd3,12'd3,12'd61,12'd3,12'd61,12'd44,12'd3,12'd44})$fatal(1,"custom ROI centroid/outside black object");
    custom_seen=custom_seen+1;
   end
   if(custom_reject)custom_rejected=custom_rejected+1;
   if(invalid_cv!==0||invalid_drop!==0||invalid_busy!==0)$fatal(1,"illegal configuration became busy/valid/dropped");
   if(invalid_fe)begin
    if(invalid_reject!=={INVALID_CASES{1'b1}})$fatal(1,"illegal ROI/threshold/source not rejected at frame_end: %h",invalid_reject);
    invalid_frames=invalid_frames+1;
   end else if(invalid_reject!==0)$fatal(1,"illegal-config reject pulse length");
  end
 end
 task default_frame(input integer outer_edges);
  begin
   default_expected=outer_edges?{12'd0,12'd0,12'd64,12'd0,12'd64,12'd48,12'd0,12'd48}:
    {12'd31,12'd23,12'd32,12'd23,12'd32,12'd24,12'd31,12'd24};
   for(integer c=0;c<4;c=c+1)begin
    @(negedge clk);default_pv=1;default_fs=(c==0);default_fe=(c==3);
    default_x=(c==1||c==2)?(outer_edges?64:32):(outer_edges?0:31);
    default_y=(c>=2)?(outer_edges?48:24):(outer_edges?0:23);
   end
   @(negedge clk);default_pv=0;default_fs=0;default_fe=0;
  end
 endtask
 task custom_frame(input [23:0] color);
  integer bx,by;
  begin
   // The first and last valid samples are black objects outside every ROI.
   @(negedge clk);custom_pv=1;custom_fs=1;custom_fe=0;custom_x=0;custom_y=0;custom_rgb=24'h202020;
   for(integer c=0;c<4;c=c+1)begin
    bx=(c==1||c==2)?60:2;by=(c>=2)?43:2;
    for(integer k=0;k<4;k=k+1)begin
     @(negedge clk);custom_fs=0;custom_x=bx+k%2;custom_y=by+k/2;custom_rgb=color;
    end
   end
   @(negedge clk);custom_x=32;custom_y=24;custom_rgb=24'h202020;
   @(negedge clk);custom_fe=1;custom_x=64;custom_y=48;
   @(negedge clk);custom_pv=0;custom_fs=0;custom_fe=0;
  end
 endtask
 initial begin
  repeat(3)@(negedge clk);rst_n=1;
  // Neither white valid pixels nor frames with no valid pixels hide bad parameters.
  @(negedge clk);invalid_pv=1;invalid_fs=1;invalid_fe=1;
  @(negedge clk);invalid_pv=0;invalid_fs=0;invalid_fe=0;
  @(negedge clk);invalid_fs=1;invalid_fe=1;
  @(negedge clk);invalid_fs=0;invalid_fe=0;
  // Occupy each legal part of the ROI layout without hitting shared edges.
  for(integer c=0;c<4;c=c+1)begin
   @(negedge clk);invalid_pv=1;invalid_fs=(c==0);invalid_fe=(c==3);invalid_rgb=24'h000000;
   invalid_x=(c==1||c==2)?10:2;invalid_y=(c>=2)?10:2;
  end
  @(negedge clk);invalid_pv=0;invalid_fs=0;invalid_fe=0;
  default_frame(0);repeat(400)@(negedge clk);
  default_frame(1);repeat(400)@(negedge clk);
  custom_frame(24'h202020);repeat(400)@(negedge clk);
  custom_frame(24'h1f2020);repeat(5)@(negedge clk);
  if(default_seen!=2||custom_seen!=1||custom_rejected!=1||invalid_frames!=3)$fatal(1,"ROI test totals");
  test_passed=1;$display("MARKER_CONFIG_PASS odd_roi_frames=2 custom_roi_frames=1 lower_threshold=32 lower_31_rejected=1 illegal_configs=22 frames_without_black=2 shared_edge_pairs=6");$finish;
 end
 initial begin #30000;$fatal(1,"MARKER_CONFIG timeout");end
endmodule
