// Datapath boundary with A's frame cache. Return metadata with memory pixels.
// req_valid includes out-of-bounds positions: A must respond black without reading.
// No backpressure: buffer/cache must sustain the requested rate or schedule input.
module perspective_core #(parameter SRC_W=640,SRC_H=480)(
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
 wire [19:0] sx,sy;wire [25:0] coord_tag;
 perspective_coord #(.TAG_W(26)) u_coord(clk,rst_n,in_valid,dst_x,dst_y,{nearest,geometry_valid,dst_y,dst_x},
  h00,h01,h02,h10,h11,h12,h20,h21,h22,req_valid,req_error,sx,sy,coord_tag);
 wire nn=coord_tag[25];
 wire [12:0] xn={1'b0,sx[19:8]}+sx[7],yn={1'b0,sy[19:8]}+sy[7];
 wire [12:0] bx=nn?xn:{1'b0,sx[19:8]},by=nn?yn:{1'b0,sy[19:8]};
 wire [12:0] ex=nn?bx:(bx<SRC_W-1?bx+13'd1:bx);
 wire [12:0] ey=nn?by:(by<SRC_H-1?by+13'd1:by);
 assign req_inside=req_valid&&coord_tag[24]&&!req_error&&(nn ? xn<SRC_W&&yn<SRC_H : sx<=(SRC_W-1)*256&&sy<=(SRC_H-1)*256);
 assign req_tag=coord_tag[23:0];
 assign addr00=req_inside ? by*SRC_W+bx : 24'd0;
 assign addr10=req_inside ? by*SRC_W+ex : 24'd0;
 assign addr01=req_inside ? ey*SRC_W+bx : 24'd0;
 assign addr11=req_inside ? ey*SRC_W+ex : 24'd0;
 assign req_fx=req_inside&&!nn?sx[7:0]:8'd0;
 assign req_fy=req_inside&&!nn?sy[7:0]:8'd0;
 bilinear_interp u_interp(clk,rst_n,rsp_valid,rsp_inside,p00,p10,p01,p11,rsp_fx,rsp_fy,rsp_tag,out_valid,out_rgb,out_tag);
endmodule
