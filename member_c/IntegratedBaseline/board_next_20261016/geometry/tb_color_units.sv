`timescale 1ns/1ps
`ifndef DETECTOR_MODULE
`define DETECTOR_MODULE marker_detector
`endif
module tb_color_units;
reg clk=0;always #8.754037 clk=~clk;
reg rst_n=0,pixel_valid=0,frame_start=0,frame_end=0;reg[11:0]pixel_x=0,pixel_y=0;reg[23:0]rgb=0;
wire corners_valid,frame_reject,frame_dropped,busy;wire[11:0]x0,y0,x1,y1,x2,y2,x3,y3;
`DETECTOR_MODULE #(.SRC_W(1920),.SRC_H(1080),.MIN_PIXELS(16),.MAX_PIXELS(4096),.MAX_SPAN(128)) dut(.*);
integer cx[0:3],cy[0:3];reg[23:0]colors[0:3];reg got_valid=0,got_reject=0;
always @(posedge clk)if(rst_n)begin if(corners_valid)got_valid<=1;if(frame_reject||frame_dropped)got_reject<=1;end
task rect;input integer x,y,rx,ry;input[23:0]color;begin
for(integer yy=-ry;yy<=ry;yy=yy+1)for(integer xx=-rx;xx<=rx;xx=xx+1)begin
pixel_valid=1;pixel_x=x+xx;pixel_y=y+yy;rgb=color;@(negedge clk);end
pixel_valid=0;
end endtask
task test_case;input integer kind;input bit expect_valid;reg[23:0]tmp;begin
cx[0]=650;cy[0]=70;cx[1]=1250;cy[1]=110;cx[2]=1320;cy[2]=1010;cx[3]=590;cy[3]=960;
colors[0]=24'h64141e;colors[1]=24'h14be1e;colors[2]=24'ha0be14;colors[3]=24'h2814b4;
if(kind==1)begin cx[0]=1100;cy[0]=100;cx[1]=1700;cy[1]=160;cx[2]=1650;cy[2]=950;cx[3]=1150;cy[3]=900;end
if(kind==2)begin tmp=colors[0];colors[0]=colors[3];colors[3]=tmp;end
if(kind==4)for(integer c=0;c<4;c=c+1)colors[c]=0;
if(kind==9)begin cx[0]=300;cy[0]=200;cx[1]=1400;cy[1]=200;cx[2]=700;cy[2]=400;cx[3]=500;cy[3]=800;end
if(kind==10)begin cx[0]=800;cy[0]=500;cx[1]=840;cy[1]=500;cx[2]=840;cy[2]=540;cx[3]=800;cy[3]=540;end
@(negedge clk);got_valid=0;got_reject=0;frame_start=1;
@(negedge clk);frame_start=0;
for(integer c=0;c<4;c=c+1)begin
if(kind==3&&c==2)begin end
else if(kind==5&&c==3)rect(cx[c],cy[c],0,0,colors[c]);
else if(kind==6&&c==0)rect(cx[c],cy[c],70,70,colors[c]);
else if(kind==7&&c==0)begin rect(cx[c]-40,cy[c],3,3,colors[c]);rect(cx[c]+40,cy[c],3,3,colors[c]);end
else if(kind==8&&c==1)rect(cx[c],cy[c],30,0,colors[c]);
else rect(cx[c],cy[c],10,10,colors[c]);
end
if(kind==11)begin pixel_valid=1;pixel_x=1920;pixel_y=20;rgb=colors[0];@(negedge clk);pixel_valid=0;end
frame_end=1;@(negedge clk);frame_end=0;repeat(500)@(negedge clk);
if(expect_valid)begin
if(!got_valid||got_reject)$fatal(1,"valid color quad rejected case=%0d",kind);
if({x0,y0,x1,y1,x2,y2,x3,y3}!={12'(cx[0]),12'(cy[0]),12'(cx[1]),12'(cy[1]),12'(cx[2]),12'(cy[2]),12'(cx[3]),12'(cy[3])})$fatal(1,"centroid/order mismatch case=%0d",kind);
end else if(got_valid||!got_reject)$fatal(1,"invalid color case accepted kind=%0d",kind);
$display("PASS color unit case=%0d expect_valid=%0b corners=%0d,%0d/%0d,%0d/%0d,%0d/%0d,%0d",kind,expect_valid,x0,y0,x1,y1,x2,y2,x3,y3);
end endtask
initial begin
repeat(5)@(negedge clk);rst_n=1;
for(integer k=0;k<12;k=k+1)test_case(k,k<2);
$display("PASS color unit12 cases canonical/dim/right-side/color-swap/missing/black/tiny/large/sparse/thin/nonconvex/small-area/outside");$finish;
end
endmodule
