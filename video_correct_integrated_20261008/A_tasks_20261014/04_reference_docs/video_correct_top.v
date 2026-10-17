`timescale 1ns/1ps
`default_nettype none
// Logical integration top, NOT a board pin top. All ports use clk.
module video_correct_top #(
 parameter SRC_W=640,SRC_H=480,OUT_W=320,OUT_H=452,UPDATE_EVERY=5,
 parameter MIN_PIXELS=16,MAX_PIXELS=4096,MAX_SPAN=128,
 parameter R_RMIN=160,R_RMAX=255,R_GMIN=0,R_GMAX=110,R_BMIN=0,R_BMAX=110,
 parameter G_RMIN=0,G_RMAX=110,G_GMIN=140,G_GMAX=255,G_BMIN=0,G_BMAX=110,
 parameter Y_RMIN=160,Y_RMAX=255,Y_GMIN=140,Y_GMAX=255,Y_BMIN=0,Y_BMAX=110,
 parameter B_RMIN=0,B_RMAX=110,B_GMIN=0,B_GMAX=110,B_BMIN=160,B_BMAX=255
)(
 input wire clk,rst_n,
 input wire src_valid,src_frame_start,src_frame_end,
 input wire [11:0] src_x,src_y, input wire [23:0] src_rgb,
 input wire dst_valid,dst_frame_start,nearest,
 input wire [11:0] dst_x,dst_y,
 output wire corners_valid,marker_reject,marker_dropped,solver_reject,
 output wire [11:0] x0,y0,x1,y1,x2,y2,x3,y3,
 output wire geometry_valid,params_pending, output wire [15:0] stale_frames,
 output wire req_valid,req_inside,req_error,
 output wire [23:0] req_tag,addr00,addr10,addr01,addr11,
 output wire [7:0] req_fx,req_fy,
 output wire out_valid, output wire [23:0] out_rgb,out_tag,
 input wire [1:0] pattern_sel,
 output wire preview_hsync,preview_vsync,preview_de,
 output wire [23:0] preview_rgb,
 output wire missing_storage
);
wire rsp_valid,rsp_inside;
wire [23:0] rsp_tag,p00,p10,p01,p11;
wire [7:0] rsp_fx,rsp_fy;
// B current baseline is instantiated without interface modifications.
b_rectifier #(.SRC_W(SRC_W),.SRC_H(SRC_H),.OUT_W(OUT_W),.OUT_H(OUT_H),
 .UPDATE_EVERY(UPDATE_EVERY),.MIN_PIXELS(MIN_PIXELS),.MAX_PIXELS(MAX_PIXELS),.MAX_SPAN(MAX_SPAN),
 .R_RMIN(R_RMIN),.R_RMAX(R_RMAX),.R_GMIN(R_GMIN),.R_GMAX(R_GMAX),.R_BMIN(R_BMIN),.R_BMAX(R_BMAX),
 .G_RMIN(G_RMIN),.G_RMAX(G_RMAX),.G_GMIN(G_GMIN),.G_GMAX(G_GMAX),.G_BMIN(G_BMIN),.G_BMAX(G_BMAX),
 .Y_RMIN(Y_RMIN),.Y_RMAX(Y_RMAX),.Y_GMIN(Y_GMIN),.Y_GMAX(Y_GMAX),.Y_BMIN(Y_BMIN),.Y_BMAX(Y_BMAX),
 .B_RMIN(B_RMIN),.B_RMAX(B_RMAX),.B_GMIN(B_GMIN),.B_GMAX(B_GMAX),.B_BMIN(B_BMIN),.B_BMAX(B_BMAX)
) u_algorithm (
  .clk(clk),
  .rst_n(rst_n),
  .src_valid(src_valid),
  .src_frame_start(src_frame_start),
  .src_frame_end(src_frame_end),
  .src_x(src_x),
  .src_y(src_y),
  .src_rgb(src_rgb),
  .dst_valid(dst_valid),
  .dst_frame_start(dst_frame_start),
  .nearest(nearest),
  .dst_x(dst_x),
  .dst_y(dst_y),
  .corners_valid(corners_valid),
  .marker_reject(marker_reject),
  .marker_dropped(marker_dropped),
  .solver_reject(solver_reject),
  .x0(x0),
  .y0(y0),
  .x1(x1),
  .y1(y1),
  .x2(x2),
  .y2(y2),
  .x3(x3),
  .y3(y3),
  .geometry_valid(geometry_valid),
  .params_pending(params_pending),
  .stale_frames(stale_frames),
  .req_valid(req_valid),
  .req_inside(req_inside),
  .req_error(req_error),
  .req_tag(req_tag),
  .addr00(addr00),
  .addr10(addr10),
  .addr01(addr01),
  .addr11(addr11),
  .req_fx(req_fx),
  .req_fy(req_fy),
  .rsp_valid(rsp_valid),
  .rsp_inside(rsp_inside),
  .rsp_tag(rsp_tag),
  .p00(p00),
  .p10(p10),
  .p01(p01),
  .p11(p11),
  .rsp_fx(rsp_fx),
  .rsp_fy(rsp_fy),
  .out_valid(out_valid),
  .out_rgb(out_rgb),
  .out_tag(out_tag)
);
frame_store_stub u_frame_store (
 .clk(clk),.rst_n(rst_n),.req_valid(req_valid),.req_inside(req_inside),
 .req_tag(req_tag),.addr00(addr00),.addr10(addr10),.addr01(addr01),.addr11(addr11),
 .req_fx(req_fx),.req_fy(req_fy),.rsp_valid(rsp_valid),.rsp_inside(rsp_inside),
 .rsp_tag(rsp_tag),.rsp_fx(rsp_fx),.rsp_fy(rsp_fy),
 .p00(p00),.p10(p10),.p01(p01),.p11(p11),.missing_storage(missing_storage)
);
// Independent C preview only. It does NOT display the algorithm result.
// Small placeholder blanking values are NOT an HDMI video-mode definition.
video_top #(.H_SYNC(12'd2),.H_BACK(12'd2),.H_ACTIVE(OUT_W),.H_FRONT(12'd2),
 .V_SYNC(12'd2),.V_BACK(12'd2),.V_ACTIVE(OUT_H),.V_FRONT(12'd2)) u_video_preview (
 .clk(clk),.rst_n(rst_n),.pattern_sel(pattern_sel),
 .hsync(preview_hsync),.vsync(preview_vsync),.de(preview_de),.rgb(preview_rgb)
);
endmodule
`default_nettype wire
