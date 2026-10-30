// Datapath boundary with A's frame cache. Return metadata with memory pixels.
// req_valid includes out-of-bounds positions: A must respond black without reading.
// No backpressure: buffer/cache must sustain the requested rate or schedule input.
module perspective_core_frozen #(
 parameter SRC_W=640,SRC_H=480,LENS_ENABLE=0,
 parameter signed [31:0] LENS_FX_Q16=SRC_W*65536,LENS_FY_Q16=SRC_H*65536,
 parameter signed [31:0] LENS_CX_Q16=(SRC_W-1)*32768,LENS_CY_Q16=(SRC_H-1)*32768,
 parameter signed [31:0] LENS_INV_FX_Q30=1073741824/SRC_W,LENS_INV_FY_Q30=1073741824/SRC_H,
 parameter signed [31:0] LENS_K1_Q26=0,LENS_K2_Q26=0,LENS_P1_Q26=0,LENS_P2_Q26=0
)(
 input wire clk,rst_n,in_valid,nearest,geometry_valid,
 input wire [11:0] dst_x,dst_y,
 input wire signed [39:0] h00,h01,h02,h10,h11,h12,h20,h21,h22,
 output wire req_valid,req_inside,req_error,
 output wire [23:0] req_tag,
 output wire [23:0] addr00,addr10,addr01,addr11,
 output wire [7:0] req_fx,req_fy,
 input wire rsp_valid,rsp_inside,
 input wire [23:0] rsp_tag,p00,p10,p01,p11,
 input wire [7:0] rsp_fx,rsp_fy,
 output wire out_valid,output wire [23:0] out_rgb,out_tag
);
 wire [19:0] ideal_x,ideal_y;wire [25:0] coord_tag;
 wire coord_valid,coord_error;wire [25:0] map_tag;
 wire signed [39:0] sx,sy;
 perspective_coord #(.TAG_W(26)) u_coord(clk,rst_n,in_valid,dst_x,dst_y,{nearest,geometry_valid,dst_y,dst_x},
  h00,h01,h02,h10,h11,h12,h20,h21,h22,coord_valid,coord_error,ideal_x,ideal_y,coord_tag);
 // The cache is sampled only once: destination -> ideal source -> distorted source.
 // Disabling the added stage keeps the original request latency unchanged.
 generate if(LENS_ENABLE)begin:g_lens
  lens_distort_coord_frozen #(.ENABLE(1),.TAG_W(26),
   .FX_Q16(LENS_FX_Q16),.FY_Q16(LENS_FY_Q16),.CX_Q16(LENS_CX_Q16),.CY_Q16(LENS_CY_Q16),
   .INV_FX_Q30(LENS_INV_FX_Q30),.INV_FY_Q30(LENS_INV_FY_Q30),
   .K1_Q26(LENS_K1_Q26),.K2_Q26(LENS_K2_Q26),.P1_Q26(LENS_P1_Q26),.P2_Q26(LENS_P2_Q26)) u_lens(
   .clk(clk),.rst_n(rst_n),.in_valid(coord_valid),.in_error(coord_error),
   .in_x(ideal_x),.in_y(ideal_y),.in_tag(coord_tag),
   .out_valid(req_valid),.out_error(req_error),.out_x(sx),.out_y(sy),.out_tag(map_tag));
 end else begin:g_no_lens
  assign req_valid=coord_valid;assign req_error=coord_error;
  assign sx=$signed({20'd0,ideal_x});assign sy=$signed({20'd0,ideal_y});assign map_tag=coord_tag;
 end endgenerate
 wire nn=map_tag[25];
 wire signed [39:0] xn=(sx+40'sd128)>>>8,yn=(sy+40'sd128)>>>8;
 wire signed [39:0] bx=nn?xn:(sx>>>8),by=nn?yn:(sy>>>8);
 wire signed [39:0] ex=nn?bx:(bx<SRC_W-1?bx+40'sd1:bx);
 wire signed [39:0] ey=nn?by:(by<SRC_H-1?by+40'sd1:by);
 assign req_inside=req_valid&&map_tag[24]&&!req_error&&
  (nn ? xn>=0&&yn>=0&&xn<SRC_W&&yn<SRC_H : sx>=0&&sy>=0&&sx<=(SRC_W-1)*256&&sy<=(SRC_H-1)*256);
 assign req_tag=map_tag[23:0];
 assign addr00=req_inside ? by*SRC_W+bx : 24'd0;
 assign addr10=req_inside ? by*SRC_W+ex : 24'd0;
 assign addr01=req_inside ? ey*SRC_W+bx : 24'd0;
 assign addr11=req_inside ? ey*SRC_W+ex : 24'd0;
 assign req_fx=req_inside&&!nn?sx[7:0]:8'd0;
 assign req_fy=req_inside&&!nn?sy[7:0]:8'd0;
 bilinear_interp u_interp(clk,rst_n,rsp_valid,rsp_inside,p00,p10,p01,p11,rsp_fx,rsp_fy,rsp_tag,out_valid,out_rgb,out_tag);
endmodule
