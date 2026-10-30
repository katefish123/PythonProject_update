// Inverse map, 1 input/clock. Three 64-bit MACs, two UQ12.8 pipeline dividers.
// E0 MAC, E1 divider input, E21 divider output, E22 final output.
module perspective_coord #(parameter TAG_W=25)(
 input wire clk,rst_n,in_valid,
 input wire [11:0] dst_x,dst_y,
 input wire [TAG_W-1:0] in_tag,
 input wire signed [39:0] h00,h01,h02,h10,h11,h12,h20,h21,h22,
 output reg out_valid,out_error,
 output reg [19:0] src_x_q,src_y_q,
 output reg [TAG_W-1:0] out_tag
);
 wire signed [63:0] xx={52'd0,dst_x}, yy={52'd0,dst_y};
 wire signed [63:0] a00={{24{h00[39]}},h00},a01={{24{h01[39]}},h01},a02={{24{h02[39]}},h02};
 wire signed [63:0] a10={{24{h10[39]}},h10},a11={{24{h11[39]}},h11},a12={{24{h12[39]}},h12};
 wire signed [63:0] a20={{24{h20[39]}},h20},a21={{24{h21[39]}},h21},a22={{24{h22[39]}},h22};


 // Exact signed40 coefficient times unsigned12 coordinate, in two products.
 // low24 is represented as positive signed25; high16 remains signed.
 // Products are explicitly sized before the 64-bit reconstruction.
 function signed [63:0] h_times_coordinate;
  input signed [39:0] coefficient;
  input [11:0] coordinate;
  reg signed [24:0] low_part;
  reg signed [15:0] high_part;
  reg signed [12:0] positive_coordinate;
  reg signed [37:0] low_product;
  reg signed [28:0] high_product;
  reg signed [63:0] low_extended,high_extended;
  begin
   low_part=$signed({1'b0,coefficient[23:0]});
   high_part=$signed(coefficient[39:24]);
   positive_coordinate=$signed({1'b0,coordinate});
   low_product=low_part*positive_coordinate;
   high_product=high_part*positive_coordinate;
   low_extended={{26{low_product[37]}},low_product};
   high_extended={{35{high_product[28]}},high_product};
   h_times_coordinate=low_extended+(high_extended<<<24);
  end
 endfunction

 reg signed [63:0] nx,ny,den;
 reg v0;reg [TAG_W-1:0] tag0;
 wire bad=den<=64'sd1048576||nx<0||ny<0||(|nx[63:48])||(|ny[63:48])||(|den[63:48]);
 wire vx,vy,ex,ey;
 wire [19:0] qx,qy;
 wire [TAG_W:0] tx,ty;
 scaled_div_pipe #(.TAG_W(TAG_W+1)) ux(clk,rst_n,v0,nx[47:0],den[47:0],{bad,tag0},vx,ex,qx,tx);
 scaled_div_pipe #(.TAG_W(TAG_W+1)) uy(clk,rst_n,v0,ny[47:0],den[47:0],{bad,tag0},vy,ey,qy,ty);
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin nx<=0;ny<=0;den<=1;v0<=0;tag0<=0;out_valid<=0;out_error<=0;src_x_q<=0;src_y_q<=0;out_tag<=0;end
  else begin
   nx<=h_times_coordinate(h00,dst_x)+h_times_coordinate(h01,dst_y)+a02;ny<=h_times_coordinate(h10,dst_x)+h_times_coordinate(h11,dst_y)+a12;den<=h_times_coordinate(h20,dst_x)+h_times_coordinate(h21,dst_y)+a22;
   v0<=in_valid;tag0<=in_tag;
   out_valid<=vx&&vy;out_error<=vx&&(tx[TAG_W]||ex||ey);
   src_x_q<=(tx[TAG_W]||ex||ey)?20'd0:qx;src_y_q<=(tx[TAG_W]||ex||ey)?20'd0:qy;
   out_tag<=tx[TAG_W-1:0];
  end
 end
endmodule
