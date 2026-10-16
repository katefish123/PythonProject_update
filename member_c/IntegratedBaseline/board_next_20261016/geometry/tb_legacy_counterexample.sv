`timescale 1ns/1ps
`ifndef DETECTOR_MODULE
`define DETECTOR_MODULE marker_detector
`endif
module tb_legacy_counterexample;
reg clk=0;always #8.754037 clk=~clk;
reg rst_n=0,pixel_valid=0,frame_start=0,frame_end=0;reg[11:0]pixel_x=0,pixel_y=0;reg[23:0]rgb=0;
wire corners_valid,frame_reject,frame_dropped,busy;wire[11:0]x0,y0,x1,y1,x2,y2,x3,y3;
marker_detector #(.SRC_W(1920),.SRC_H(1080),.MIN_PIXELS(16),.MAX_PIXELS(4096),.MAX_SPAN(128)) dut(.*);
wire small_valid,small_reject,small_drop,small_busy;wire[11:0]sx0,sy0,sx1,sy1,sx2,sy2,sx3,sy3;
marker_detector #(.SRC_W(1920),.SRC_H(1080),.MIN_PIXELS(16),.MAX_PIXELS(4096),.MAX_SPAN(128),
.P0_XMIN(450),.P0_XMAX(481),.P0_YMIN(250),.P0_YMAX(281),.P1_XMIN(1410),.P1_XMAX(1441),.P1_YMIN(250),.P1_YMAX(281),
.P2_XMIN(1410),.P2_XMAX(1441),.P2_YMIN(790),.P2_YMAX(821),.P3_XMIN(450),.P3_XMAX(481),.P3_YMIN(790),.P3_YMAX(821)) calibrated(
.clk(clk),.rst_n(rst_n),.pixel_valid(pixel_valid),.frame_start(frame_start),.frame_end(frame_end),.pixel_x(pixel_x),.pixel_y(pixel_y),.rgb(rgb),
.corners_valid(small_valid),.frame_reject(small_reject),.frame_dropped(small_drop),.busy(small_busy),.x0(sx0),.y0(sy0),.x1(sx1),.y1(sy1),.x2(sx2),.y2(sy2),.x3(sx3),.y3(sy3));
wire color_valid,color_reject,color_drop,color_busy;wire[11:0]tx0,ty0,tx1,ty1,tx2,ty2,tx3,ty3;
color_marker_detector candidate(.clk(clk),.rst_n(rst_n),.pixel_valid(pixel_valid),.frame_start(frame_start),.frame_end(frame_end),.pixel_x(pixel_x),.pixel_y(pixel_y),.rgb(rgb),
.corners_valid(color_valid),.frame_reject(color_reject),.frame_dropped(color_drop),.busy(color_busy),.x0(tx0),.y0(ty0),.x1(tx1),.y1(ty1),.x2(tx2),.y2(ty2),.x3(tx3),.y3(ty3));
reg seen_old=0,seen_small=0,seen_color=0;
always @(posedge clk)begin if(corners_valid)seen_old=1;if(small_valid)seen_small=1;if(color_valid)seen_color=1;end
integer cx[0:3],cy[0:3];reg[23:0]colors[0:3];reg got_valid=0,got_reject=0;
always @(posedge clk)if(rst_n)begin if(corners_valid)got_valid<=1;if(frame_reject||frame_dropped)got_reject<=1;end
initial begin
cx[0]=480;cy[0]=270;cx[1]=1440;cy[1]=270;cx[2]=1440;cy[2]=810;cx[3]=480;cy[3]=810;
repeat(5)@(negedge clk);rst_n=1;frame_start=1;@(negedge clk);frame_start=0;
for(integer c=0;c<4;c=c+1)for(integer yy=-7;yy<=7;yy=yy+1)for(integer xx=-7;xx<=7;xx=xx+1)begin
pixel_valid=1;pixel_x=cx[c]+xx;pixel_y=cy[c]+yy;rgb=0;@(negedge clk);end
pixel_valid=0;frame_end=1;@(negedge clk);frame_end=0;repeat(500)@(negedge clk);
if(!seen_old||seen_color)$fatal(1,"background black-block counterexample absent");
$display("PASS legacy counterexample default ROIs accept unrelated black blocks at480,270/1440,270/1440,810/480,810; color rejects");
seen_old=0;seen_small=0;seen_color=0;frame_start=1;@(negedge clk);frame_start=0;
for(integer y=0;y<1080;y=y+1)for(integer x=0;x<1920;x=x+1)begin pixel_valid=1;pixel_x=x;pixel_y=y;rgb=0;@(negedge clk);end
pixel_valid=0;frame_end=1;@(negedge clk);frame_end=0;repeat(500)@(negedge clk);
if(seen_old||!seen_small||seen_color)$fatal(1,"all-black ROI counterexample absent");
if({sx0,sy0,sx1,sy1,sx2,sy2,sx3,sy3}!={12'd466,12'd266,12'd1426,12'd266,12'd1426,12'd806,12'd466,12'd806})$fatal(1,"ROI-centroid mismatch");
$display("PASS legacy all-black fullHD default ROIs reject count/span; small calibrated ROIs falsely accept fixed window centroids466,266/1426,266/1426,806/466,806; color rejects");$finish;
end
endmodule
