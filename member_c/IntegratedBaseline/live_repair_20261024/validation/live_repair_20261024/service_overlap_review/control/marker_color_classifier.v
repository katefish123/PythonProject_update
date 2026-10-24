`timescale 1ns/1ps
`default_nettype none
module marker_color_classifier #(
 parameter SRC_W=640,SRC_H=480, MIN_PIXELS=16,MAX_PIXELS=4096,MAX_SPAN=128,
 parameter BLACK_RMIN=0,BLACK_RMAX=64,BLACK_GMIN=0,BLACK_GMAX=64,BLACK_BMIN=0,BLACK_BMAX=64,
 // Inclusive, non-overlapping windows in source coordinates; P0/P1/P2/P3 = TL/TR/BR/BL.
 // Integer division places the center column/row of an odd source in right/bottom ROIs.
 parameter P0_XMIN=0,P0_XMAX=SRC_W/2-1,P0_YMIN=0,P0_YMAX=SRC_H/2-1,
 parameter P1_XMIN=SRC_W/2,P1_XMAX=SRC_W-1,P1_YMIN=0,P1_YMAX=SRC_H/2-1,
 parameter P2_XMIN=SRC_W/2,P2_XMAX=SRC_W-1,P2_YMIN=SRC_H/2,P2_YMAX=SRC_H-1,
 parameter P3_XMIN=0,P3_XMAX=SRC_W/2-1,P3_YMIN=SRC_H/2,P3_YMAX=SRC_H-1,
 parameter MARKER_MODE=1,COLOR_MIN=64,COLOR_DELTA=32,MIN_SIDE=3,ASPECT_LIMIT=6,COMPACT_NUM=1,COMPACT_DEN=2,
 parameter MIN_QUAD_AREA=SRC_W*SRC_H/50,MIN_QUAD_CROSS=64,MIN_QUAD_EXTENT=SRC_H/16
)(
 input wire[23:0]rgb,input wire[11:0]pixel_x,pixel_y,output wire[3:0]hit
);
 wire[8:0]r={1'b0,rgb[23:16]},g={1'b0,rgb[15:8]},b={1'b0,rgb[7:0]};
 wire yellow=r>=COLOR_MIN&&g>=COLOR_MIN&&r>=b+COLOR_DELTA&&g>=b+COLOR_DELTA&&2*r<=3*g&&2*g<=3*r;
 wire red=r>=COLOR_MIN&&r>=g+COLOR_DELTA&&r>=b+COLOR_DELTA&&!yellow;
 wire green=g>=COLOR_MIN&&g>=r+COLOR_DELTA&&g>=b+COLOR_DELTA&&!yellow;
 wire blue=b>=COLOR_MIN&&b>=r+COLOR_DELTA&&b>=g+COLOR_DELTA;
 wire black=r>=BLACK_RMIN&&r<=BLACK_RMAX&&g>=BLACK_GMIN&&g<=BLACK_GMAX&&b>=BLACK_BMIN&&b<=BLACK_BMAX;
 assign hit[0]=MARKER_MODE==1?red:(black&&pixel_x>=P0_XMIN&&pixel_x<=P0_XMAX&&pixel_y>=P0_YMIN&&pixel_y<=P0_YMAX);
 assign hit[1]=MARKER_MODE==1?green:(black&&pixel_x>=P1_XMIN&&pixel_x<=P1_XMAX&&pixel_y>=P1_YMIN&&pixel_y<=P1_YMAX);
 assign hit[2]=MARKER_MODE==1?yellow:(black&&pixel_x>=P2_XMIN&&pixel_x<=P2_XMAX&&pixel_y>=P2_YMIN&&pixel_y<=P2_YMAX);
 assign hit[3]=MARKER_MODE==1?blue:(black&&pixel_x>=P3_XMIN&&pixel_x<=P3_XMAX&&pixel_y>=P3_YMIN&&pixel_y<=P3_YMAX);
endmodule
`default_nettype wire
