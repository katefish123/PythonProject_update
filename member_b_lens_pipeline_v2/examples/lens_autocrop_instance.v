`include "examples/r50_18mm_viewport.vh"
// Generated viewport binding: source size, lens calibration and destination-to-
// ideal-source H come from one SAFE header. No external geometry or H is needed.
module lens_autocrop_instance(
 input wire clk,rst_n,in_valid,nearest,
 input wire [11:0] dst_x,dst_y,
 output wire req_valid,req_inside,req_error,
 output wire [23:0] req_tag,addr00,addr10,addr01,addr11,
 output wire [7:0] req_fx,req_fy,
 input wire rsp_valid,rsp_inside,
 input wire [23:0] rsp_tag,p00,p10,p01,p11,
 input wire [7:0] rsp_fx,rsp_fy,
 output wire out_valid,output wire [23:0] out_rgb,out_tag
);
 wire geometry_valid=(dst_x<`SAFE_DST_W)&&(dst_y<`SAFE_DST_H);
 perspective_core #(.SRC_W(`SAFE_SRC_W),.SRC_H(`SAFE_SRC_H),.LENS_ENABLE(1),
  .LENS_FX_Q16(`SAFE_FX_Q16),.LENS_FY_Q16(`SAFE_FY_Q16),
  .LENS_CX_Q16(`SAFE_CX_Q16),.LENS_CY_Q16(`SAFE_CY_Q16),
  .LENS_INV_FX_Q30(`SAFE_INV_FX_Q30),.LENS_INV_FY_Q30(`SAFE_INV_FY_Q30),
  .LENS_K1_Q26(`SAFE_K1_Q26),.LENS_K2_Q26(`SAFE_K2_Q26),
  .LENS_P1_Q26(`SAFE_P1_Q26),.LENS_P2_Q26(`SAFE_P2_Q26)) u_core(
  .clk(clk),.rst_n(rst_n),.in_valid(in_valid),.nearest(nearest),.geometry_valid(geometry_valid),
  .dst_x(dst_x),.dst_y(dst_y),
  .h00(`SAFE_H00_Q24),.h01(`SAFE_H01_Q24),.h02(`SAFE_H02_Q24),
  .h10(`SAFE_H10_Q24),.h11(`SAFE_H11_Q24),.h12(`SAFE_H12_Q24),
  .h20(`SAFE_H20_Q24),.h21(`SAFE_H21_Q24),.h22(`SAFE_H22_Q24),
  .req_valid(req_valid),.req_inside(req_inside),.req_error(req_error),.req_tag(req_tag),
  .addr00(addr00),.addr10(addr10),.addr01(addr01),.addr11(addr11),.req_fx(req_fx),.req_fy(req_fy),
  .rsp_valid(rsp_valid),.rsp_inside(rsp_inside),.rsp_tag(rsp_tag),
  .p00(p00),.p10(p10),.p01(p01),.p11(p11),.rsp_fx(rsp_fx),.rsp_fy(rsp_fy),
  .out_valid(out_valid),.out_rgb(out_rgb),.out_tag(out_tag));
endmodule
