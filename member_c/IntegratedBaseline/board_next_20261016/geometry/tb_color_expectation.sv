`timescale 1ns/1ps
`ifndef DETECTOR_MODULE
`define DETECTOR_MODULE marker_detector
`endif
module tb_color_expectation;
reg clk=0;always #8.754037 clk=~clk;
reg rst_n=0,pixel_valid=0,frame_start=0,frame_end=0;reg[11:0]pixel_x=0,pixel_y=0;reg[23:0]rgb=0;
wire corners_valid,frame_reject,frame_dropped,busy;wire[11:0]x0,y0,x1,y1,x2,y2,x3,y3;
`DETECTOR_MODULE #(.SRC_W(1920),.SRC_H(1080),.MIN_PIXELS(16),.MAX_PIXELS(4096),.MAX_SPAN(128)) dut(.*);
integer cx[0:3],cy[0:3];reg[23:0]colors[0:3];reg got_valid=0,got_reject=0;
always @(posedge clk)if(rst_n)begin if(corners_valid)got_valid<=1;if(frame_reject||frame_dropped)got_reject<=1;end
initial begin
cx[0]=650;cy[0]=70;cx[1]=1250;cy[1]=110;cx[2]=1320;cy[2]=1010;cx[3]=590;cy[3]=960;
colors[0]=24'he02020;colors[1]=24'h20d020;colors[2]=24'he0d020;colors[3]=24'h2020e0;
repeat(5)@(negedge clk);rst_n=1;frame_start=1;@(negedge clk);frame_start=0;
for(integer c=0;c<4;c=c+1)for(integer yy=-10;yy<=10;yy=yy+1)for(integer xx=-10;xx<=10;xx=xx+1)begin
pixel_valid=1;pixel_x=cx[c]+xx;pixel_y=cy[c]+yy;rgb=colors[c];@(negedge clk);end
pixel_valid=0;frame_end=1;@(negedge clk);frame_end=0;
repeat(500)@(negedge clk);
if(!got_valid||got_reject)$fatal(1,"FOUR_COLOR_REQUIRED canonical redTL/greenTR/yellowBR/blueBL rejected by black-only mode");
if({x0,y0,x1,y1,x2,y2,x3,y3}!={12'd650,12'd70,12'd1250,12'd110,12'd1320,12'd1010,12'd590,12'd960})$fatal(1,"corner color/order/centroid mismatch");
$display("PASS four-color source1920x1080 exact corners redTL650,70 greenTR1250,110 yellowBR1320,1010 blueBL590,960");$finish;
end
endmodule
