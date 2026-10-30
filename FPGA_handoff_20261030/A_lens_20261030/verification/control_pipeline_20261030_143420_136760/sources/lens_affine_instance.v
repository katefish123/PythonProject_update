`timescale 1ns/1ps
`default_nettype none
// Destination-to-ideal-source affine transform followed by B's calibrated
// Brown lens mapper and one source-image resampling. Coefficients are Q24.
// The caller holds the entire affine descriptor unchanged for one frame.
module lens_affine_instance(
 input wire clk,rst_n,in_valid,nearest,input wire[239:0]affine,
 input wire[11:0]dst_x,dst_y,
 output reg req_valid,req_inside,req_error,
 output reg[23:0]req_tag,addr00,addr10,addr01,addr11,
 output reg[7:0]req_fx,req_fy,
 input wire rsp_valid,rsp_inside,input wire[23:0]rsp_tag,p00,p10,p01,p11,input wire[7:0]rsp_fx,rsp_fy,
 output wire out_valid,output wire[23:0]out_rgb,out_tag
);
 function signed[63:0]times_coordinate;
 input signed[39:0]h;input[11:0]p;
 reg signed[24:0]lo;reg signed[15:0]hi;reg signed[12:0]pp;
 reg signed[37:0]lp;reg signed[28:0]hp;
 begin lo=$signed({1'b0,h[23:0]});hi=$signed(h[39:24]);pp=$signed({1'b0,p});lp=lo*pp;hp=hi*pp;
 times_coordinate=$signed({{26{lp[37]}},lp})+($signed({{35{hp[28]}},hp})<<<24);end endfunction
 reg v0,v1;reg[24:0]tag0,tag1;
 reg signed[63:0]px0,px1,py0,py1,tx0,ty0,nx,ny;
 wire signed[39:0]h00=affine[0+:40],h01=affine[40+:40],h02=affine[80+:40],h10=affine[120+:40],h11=affine[160+:40],h12=affine[200+:40];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin v0<=0;v1<=0;tag0<=0;tag1<=0;px0<=0;px1<=0;py0<=0;py1<=0;tx0<=0;ty0<=0;nx<=0;ny<=0;end
  else begin
   v0<=in_valid;v1<=v0;tag0<={nearest,dst_y,dst_x};tag1<=tag0;
   px0<=times_coordinate(h00,dst_x);px1<=times_coordinate(h01,dst_y);tx0<={{24{h02[39]}},h02};
   py0<=times_coordinate(h10,dst_x);py1<=times_coordinate(h11,dst_y);ty0<={{24{h12[39]}},h12};
   nx<=px0+px1+tx0;ny<=py0+py1+ty0;
  end
 end
 wire affine_valid=nx>=0&&ny>=0&&nx<64'sd68719476736&&ny<64'sd68719476736;
 wire lens_valid,lens_error;wire signed[39:0]lens_x,lens_y;wire[25:0]lens_tag;
 // Calibration values exactly match the source-locked R50/18mm trial binding.
 lens_distort_coord #(.ENABLE(1),.TAG_W(26),
 .FX_Q16(32'sh063f1780),.FY_Q16(32'sh063c708c),.CX_Q16(32'sh03a57f37),.CY_Q16(32'sh020d44c1),
 .INV_FX_Q30(32'sh000a3eee),.INV_FY_Q30(32'sh000a4349),
 .K1_Q26(32'sh000babdf),.K2_Q26(32'shffcbeb77),.P1_Q26(32'shfffbd48f),.P2_Q26(32'shfffc4b3a)) lens(
 .clk(clk),.rst_n(rst_n),.in_valid(v1),.in_error(1'b0),
 .in_x(affine_valid?nx[35:16]:20'd0),.in_y(affine_valid?ny[35:16]:20'd0),
 .in_tag({tag1[24],affine_valid,tag1[23:0]}),.out_valid(lens_valid),.out_error(lens_error),.out_x(lens_x),.out_y(lens_y),.out_tag(lens_tag));
 wire nn=lens_tag[25];
 wire signed[39:0]xn=(lens_x+40'sd128)>>>8,yn=(lens_y+40'sd128)>>>8;
 wire signed[39:0]bx=nn?xn:(lens_x>>>8),by=nn?yn:(lens_y>>>8);
 wire signed[39:0]ex=nn?bx:(bx<1919?bx+40'sd1:bx),ey=nn?by:(by<1079?by+40'sd1:by);
 wire inside_now=lens_valid&&lens_tag[24]&&!lens_error&&(nn?xn>=0&&yn>=0&&xn<1920&&yn<1080:lens_x>=0&&lens_y>=0&&lens_x<=40'sd491264&&lens_y<=40'sd276224);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin req_valid<=0;req_inside<=0;req_error<=0;req_tag<=0;addr00<=0;addr10<=0;addr01<=0;addr11<=0;req_fx<=0;req_fy<=0;end
  else begin
   req_valid<=lens_valid;req_inside<=inside_now;req_error<=lens_error;req_tag<=lens_tag[23:0];
   addr00<=inside_now?by*1920+bx:24'd0;addr10<=inside_now?by*1920+ex:24'd0;
   addr01<=inside_now?ey*1920+bx:24'd0;addr11<=inside_now?ey*1920+ex:24'd0;
   req_fx<=inside_now&&!nn?lens_x[7:0]:8'd0;req_fy<=inside_now&&!nn?lens_y[7:0]:8'd0;
  end
 end
 bilinear_interp interp(clk,rst_n,rsp_valid,rsp_inside,p00,p10,p01,p11,rsp_fx,rsp_fy,rsp_tag,out_valid,out_rgb,out_tag);
endmodule
`default_nettype wire