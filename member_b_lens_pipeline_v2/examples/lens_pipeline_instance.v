`include "examples/r50_18mm_calibration.vh"
// H maps destination centers to the IDEAL source plane, before lens distortion.
// Hold H constant over a frame (or atomically commit it at the frame boundary).
// This example has no corner detector; the caller supplies H explicitly.
module lens_pipeline_instance(
 input wire clk,rst_n,in_valid,nearest,geometry_valid,
 input wire [11:0] dst_x,dst_y,
 input wire signed [39:0] h00,h01,h02,h10,h11,h12,h20,h21,h22,
 output wire req_valid,req_inside,req_error,
 output wire [23:0] req_tag,addr00,addr10,addr01,addr11,
 output wire [7:0] req_fx,req_fy,
 input wire rsp_valid,rsp_inside,
 input wire [23:0] rsp_tag,p00,p10,p01,p11,
 input wire [7:0] rsp_fx,rsp_fy,
 output wire out_valid,output wire [23:0] out_rgb,out_tag
);
 perspective_core #(.SRC_W(1920),.SRC_H(1080),.LENS_ENABLE(1),
  .LENS_FX_Q16(`LENS_FX_Q16),.LENS_FY_Q16(`LENS_FY_Q16),
  .LENS_CX_Q16(`LENS_CX_Q16),.LENS_CY_Q16(`LENS_CY_Q16),
  .LENS_INV_FX_Q30(`LENS_INV_FX_Q30),.LENS_INV_FY_Q30(`LENS_INV_FY_Q30),
  .LENS_K1_Q26(`LENS_K1_Q26),.LENS_K2_Q26(`LENS_K2_Q26),
  .LENS_P1_Q26(`LENS_P1_Q26),.LENS_P2_Q26(`LENS_P2_Q26)) u_core(
  .clk(clk),.rst_n(rst_n),.in_valid(in_valid),.nearest(nearest),.geometry_valid(geometry_valid),
  .dst_x(dst_x),.dst_y(dst_y),
  .h00(h00),.h01(h01),.h02(h02),.h10(h10),.h11(h11),.h12(h12),.h20(h20),.h21(h21),.h22(h22),
  .req_valid(req_valid),.req_inside(req_inside),.req_error(req_error),.req_tag(req_tag),
  .addr00(addr00),.addr10(addr10),.addr01(addr01),.addr11(addr11),.req_fx(req_fx),.req_fy(req_fy),
  .rsp_valid(rsp_valid),.rsp_inside(rsp_inside),.rsp_tag(rsp_tag),
  .p00(p00),.p10(p10),.p01(p01),.p11(p11),.rsp_fx(rsp_fx),.rsp_fy(rsp_fy),
  .out_valid(out_valid),.out_rgb(out_rgb),.out_tag(out_tag));
endmodule
