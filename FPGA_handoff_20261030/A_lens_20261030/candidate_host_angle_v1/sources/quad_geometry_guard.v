`timescale 1ns/1ps
`default_nettype none
module quad_geometry_guard #(
 parameter SRC_W=1920,SRC_H=1080,MIN_AREA=SRC_W*SRC_H/50,MIN_CROSS=64,MIN_EXTENT=SRC_H/16
)(input wire[11:0]x0,y0,x1,y1,x2,y2,x3,y3,output wire valid);
 function signed[26:0]turn;
 input[11:0]ax,ay,bx,by,cx,cy;
 reg signed[12:0]dx0,dy0,dx1,dy1;
 reg signed[25:0]p0,p1;
 begin
 dx0=$signed({1'b0,bx})-$signed({1'b0,ax});dy0=$signed({1'b0,by})-$signed({1'b0,ay});
 dx1=$signed({1'b0,cx})-$signed({1'b0,bx});dy1=$signed({1'b0,cy})-$signed({1'b0,by});
 p0=dx0*dy1;p1=dy0*dx1;turn={p0[25],p0}-{p1[25],p1};
 end endfunction
 // The two triangle turns equal the positive twice-polygon area.
 wire signed[27:0]area2=$signed(turn(x0,y0,x1,y1,x2,y2))+$signed(turn(x2,y2,x3,y3,x0,y0));
 assign valid=x0<SRC_W&&x1<SRC_W&&x2<SRC_W&&x3<SRC_W&&y0<SRC_H&&y1<SRC_H&&y2<SRC_H&&y3<SRC_H
 &&turn(x0,y0,x1,y1,x2,y2)>=MIN_CROSS&&turn(x1,y1,x2,y2,x3,y3)>=MIN_CROSS
 &&turn(x2,y2,x3,y3,x0,y0)>=MIN_CROSS&&turn(x3,y3,x0,y0,x1,y1)>=MIN_CROSS
 &&area2>=2*MIN_AREA
 &&({1'b0,x1}+x2)>=({1'b0,x0}+x3)+MIN_EXTENT
 &&({1'b0,y2}+y3)>=({1'b0,y0}+y1)+MIN_EXTENT;
endmodule
`default_nettype wire
