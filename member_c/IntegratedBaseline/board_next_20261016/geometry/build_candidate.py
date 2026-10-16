from pathlib import Path
here=Path('D:/FPGA/worktrees/c_pipeline_next/member_c/IntegratedBaseline/board_next_20261016/geometry')
black=Path('D:/FPGA/output/c_stream_board_v4s_20261016/rtl/algo/marker_detector.v').read_text()
params=black.split('module marker_detector #(',1)[1].split(')(\n',1)[0]
params=params.rstrip()+',\n parameter MARKER_MODE=1,COLOR_MIN=64,COLOR_DELTA=32,MIN_SIDE=3,ASPECT_LIMIT=6,COMPACT_NUM=1,COMPACT_DEN=2,\n parameter MIN_QUAD_AREA=SRC_W*SRC_H/50,MIN_QUAD_CROSS=64,MIN_QUAD_EXTENT=SRC_H/16\n'
(here/'parameters.txt').write_text(params)
# Shared classifier: both the RX event filter and proc detector instantiate this definition.
helper='''`timescale 1ns/1ps
`default_nettype none
module marker_color_classifier #(@PARAMS@)(
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
'''.replace('@PARAMS@',params)
(here/'marker_color_classifier.v').write_text(helper)
baseparams=['SRC_W','SRC_H','MIN_PIXELS','MAX_PIXELS','MAX_SPAN','BLACK_RMIN','BLACK_RMAX','BLACK_GMIN','BLACK_GMAX','BLACK_BMIN','BLACK_BMAX']+[f'P{n}_{axis}{bound}' for n in range(4) for axis in 'XY' for bound in ['MIN','MAX']]
extra=['MARKER_MODE','COLOR_MIN','COLOR_DELTA','MIN_SIDE','ASPECT_LIMIT','COMPACT_NUM','COMPACT_DEN','MIN_QUAD_AREA','MIN_QUAD_CROSS','MIN_QUAD_EXTENT']
forward=','.join(f'.{n}({n})' for n in baseparams+extra)
s=black.replace('module marker_detector #('+black.split('module marker_detector #(',1)[1].split(')(\n',1)[0], 'module color_marker_detector #('+params)
a=s.index(' wire black=');b=s.index(' reg [39:0]',a)
s=s[:a]+f' wire[3:0]hit;\n marker_color_classifier #({forward}) classify(.rgb(rgb),.pixel_x(pixel_x),.pixel_y(pixel_y),.hit(hit));\n'+s[b:]
s=s.replace('localparam CONFIG_VALID=BLACK_VALID&&SOURCE_VALID&&STATS_VALID&&P0_VALID&&P1_VALID&&P2_VALID&&P3_VALID\n  &&P01_DISJOINT&&P02_DISJOINT&&P03_DISJOINT&&P12_DISJOINT&&P13_DISJOINT&&P23_DISJOINT;', '''localparam CONFIG_VALID=SOURCE_VALID&&STATS_VALID&&((MARKER_MODE==1&&COLOR_MIN>=1&&COLOR_MIN<=255&&COLOR_DELTA>=1&&COLOR_DELTA<=127&&MIN_SIDE>=1&&ASPECT_LIMIT>=1&&COMPACT_NUM>=1&&COMPACT_DEN>=COMPACT_NUM)
  ||(MARKER_MODE==0&&BLACK_VALID&&P0_VALID&&P1_VALID&&P2_VALID&&P3_VALID&&P01_DISJOINT&&P02_DISJOINT&&P03_DISJOINT&&P12_DISJOINT&&P13_DISJOINT&&P23_DISJOINT));''')
s=s.replace(' reg good;', ''' wire quad_ok;
 quad_geometry_guard #(.SRC_W(SRC_W),.SRC_H(SRC_H),.MIN_AREA(MIN_QUAD_AREA),.MIN_CROSS(MIN_QUAD_CROSS),.MIN_EXTENT(MIN_QUAD_EXTENT)) geometry(
 .x0(cx[0]),.y0(cy[0]),.x1(cx[1]),.y1(cy[1]),.x2(cx[2]),.y2(cy[2]),.x3(cx[3]),.y3(cy[3]),.valid(quad_ok));
 wire[12:0]box_w[0:3],box_h[0:3];wire[25:0]box_area[0:3];
 genvar box;
 generate for(box=0;box<4;box=box+1)begin:compact
 assign box_w[box]={1'b0,nxmax[box]}-{1'b0,nxmin[box]}+13'd1;
 assign box_h[box]={1'b0,nymax[box]}-{1'b0,nymin[box]}+13'd1;
 assign box_area[box]=box_w[box]*box_h[box];
 end endgenerate
 reg good;''')
s=s.replace('   if(nc[j]<MIN_PIXELS||nc[j]>MAX_PIXELS||(nxmax[j]-nxmin[j])>MAX_SPAN||(nymax[j]-nymin[j])>MAX_SPAN) good=0;', '''   if(nc[j]<MIN_PIXELS||nc[j]>MAX_PIXELS||(nxmax[j]-nxmin[j])>MAX_SPAN||(nymax[j]-nymin[j])>MAX_SPAN
    ||(MARKER_MODE==1&&(box_w[j]<MIN_SIDE||box_h[j]<MIN_SIDE||box_w[j]>box_h[j]*ASPECT_LIMIT||box_h[j]>box_w[j]*ASPECT_LIMIT||nc[j]*COMPACT_DEN<box_area[j]*COMPACT_NUM))) good=0;''')
s=s.replace('     corners_valid<=1;state<=0;', '     if(MARKER_MODE==0||quad_ok)corners_valid<=1;else frame_reject<=1;state<=0;')
s='// Candidate color classifier and shape guards; integer centroid/divider flow follows accepted A.\n'+s
(here/'color_marker_detector.v').write_text(s)
# Candidate copy of the CDC adapter, external ports and packet layout unchanged.
a=Path('D:/FPGA/output/c_stream_board_v4s_20261016/rtl/stream/continuous_capture_geometry.v')
if not a.exists():a=Path('D:/FPGA/worktrees/c_pipeline_next/member_c/IntegratedBaseline/stream_video_20261015/capture_continuous/continuous_capture_geometry.v')
s=a.read_text();oldp=s.split('module continuous_capture_geometry #(',1)[1].split(')(\n',1)[0]
s=s.replace(oldp,oldp.rstrip()+',\n parameter MARKER_MODE=1,COLOR_MIN=64,COLOR_DELTA=32,MIN_SIDE=3,ASPECT_LIMIT=6,COMPACT_NUM=1,COMPACT_DEN=2,\n parameter MIN_QUAD_AREA=SRC_W*SRC_H/50,MIN_QUAD_CROSS=64,MIN_QUAD_EXTENT=SRC_H/16\n')
a=s.index(' wire black=');b=s.index(' reg start_sent,overflow;',a)
s=s[:a]+f' wire[3:0]sample_hit;\n marker_color_classifier #({forward}) sample_classify(.rgb(tap_sample_rgb),.pixel_x(tap_sample_x),.pixel_y(tap_sample_y),.hit(sample_hit));\n wire contribution=|sample_hit;\n'+s[b:]
s=s.replace(' marker_detector #(', ' color_marker_detector #('+','.join(f'.{n}({n})' for n in extra)+',')
(here/'continuous_capture_geometry.v').write_text(s)
