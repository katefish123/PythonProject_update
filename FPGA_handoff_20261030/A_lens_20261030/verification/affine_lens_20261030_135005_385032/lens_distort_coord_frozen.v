// Brown k1/k2/p1/p2 ideal-pixel -> observed-pixel inverse sampling map.
// Verilog-2001, one request per clock, no divider or real arithmetic.
// Ten register stages: request captured at E0, response at E9 (9 intervals).
// Bypass and numerical errors have identical latency. rst_n flushes all valids.
module lens_distort_coord_frozen #(
 parameter integer ENABLE=1,
 parameter integer TAG_W=26,
 parameter signed [31:0] FX_Q16=32'sd65536,
 parameter signed [31:0] FY_Q16=32'sd65536,
 parameter signed [31:0] CX_Q16=32'sd0,
 parameter signed [31:0] CY_Q16=32'sd0,
 parameter signed [31:0] INV_FX_Q30=32'sd1073741824,
 parameter signed [31:0] INV_FY_Q30=32'sd1073741824,
 parameter signed [31:0] K1_Q26=32'sd0,
 parameter signed [31:0] K2_Q26=32'sd0,
 parameter signed [31:0] P1_Q26=32'sd0,
 parameter signed [31:0] P2_Q26=32'sd0
)(
 input wire clk,rst_n,in_valid,in_error,
 input wire [19:0] in_x,in_y,
 input wire [TAG_W-1:0] in_tag,
 output wire out_valid,out_error,
 output reg signed [39:0] out_x,out_y,
 output wire [TAG_W-1:0] out_tag
);
 localparam integer STAGES=10;
 localparam integer BYPASS=(ENABLE==0)||
  ((K1_Q26==0)&&(K2_Q26==0)&&(P1_Q26==0)&&(P2_Q26==0));
 reg [STAGES-1:0] valid_pipe,error_pipe;
 reg [TAG_W-1:0] tag_pipe[0:STAGES-1];
 reg [19:0] x_pipe[0:STAGES-1],y_pipe[0:STAGES-1];
 wire normalize_error;
 wire signed [39:0] mapped_x8,mapped_y8;
 integer i;
 assign out_valid=valid_pipe[STAGES-1];
 assign out_error=error_pipe[STAGES-1];
 assign out_tag=tag_pipe[STAGES-1];

 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   valid_pipe<=0;error_pipe<=0;out_x<=0;out_y<=0;
   for(i=0;i<STAGES;i=i+1)begin tag_pipe[i]<=0;x_pipe[i]<=0;y_pipe[i]<=0;end
  end else begin
   valid_pipe[0]<=in_valid;error_pipe[0]<=in_error;
   tag_pipe[0]<=in_tag;x_pipe[0]<=in_x;y_pipe[0]<=in_y;
   valid_pipe[1]<=valid_pipe[0];error_pipe[1]<=error_pipe[0]|normalize_error;
   tag_pipe[1]<=tag_pipe[0];x_pipe[1]<=x_pipe[0];y_pipe[1]<=y_pipe[0];
   for(i=2;i<STAGES;i=i+1)begin
    valid_pipe[i]<=valid_pipe[i-1];error_pipe[i]<=error_pipe[i-1];
    tag_pipe[i]<=tag_pipe[i-1];x_pipe[i]<=x_pipe[i-1];y_pipe[i]<=y_pipe[i-1];
   end
   // Numerical errors always have zero coordinates. Geometric off-frame values
   // are signed results and are deliberately preserved for the cache contract.
   if(error_pipe[8])begin out_x<=0;out_y<=0;end
   else if(BYPASS)begin
    out_x<=$signed({20'd0,x_pipe[8]});out_y<=$signed({20'd0,y_pipe[8]});
   end else begin out_x<=mapped_x8;out_y<=mapped_y8;end
  end
 end

 generate if(BYPASS)begin: g_bypass
  assign normalize_error=1'b0;
  assign mapped_x8=40'sd0;
  assign mapped_y8=40'sd0;
 end else begin: g_map
  // E0. Extend before shifting: u_q8 is unsigned and may use all 20 bits.
  wire signed [39:0] u_q16=$signed({20'd0,in_x})<<<8;
  wire signed [39:0] v_q16=$signed({20'd0,in_y})<<<8;
  wire signed [39:0] cx40={{8{CX_Q16[31]}},CX_Q16};
  wire signed [39:0] cy40={{8{CY_Q16[31]}},CY_Q16};
  wire signed [39:0] du=u_q16-cx40,dv=v_q16-cy40;
  wire signed [71:0] norm_product_x=du*INV_FX_Q30;
  wire signed [71:0] norm_product_y=dv*INV_FY_Q30;
  reg signed [71:0] norm_x0,norm_y0;

  // E1. Range-check the full result before narrowing. Tiny positive focal
  // lengths must produce an error, never a wrapped apparently-valid x/y.
  wire signed [71:0] normalized_x=norm_x0>>>20;
  wire signed [71:0] normalized_y=norm_y0>>>20;
  assign normalize_error=(normalized_x>72'sd134217728)||
   (normalized_x< -72'sd134217728)||(normalized_y>72'sd134217728)||
   (normalized_y< -72'sd134217728);
  reg signed [31:0] x1,y1;

  // E2. Each of xx, yy and xy is independently shifted before r2 is added.
  // |x/y| <= 2*S gives xx/yy <= 4*S and r2 <= 8*S (fits signed32).
  wire signed [63:0] square_x=x1*x1,square_y=y1*y1,cross_xy=x1*y1;
  wire signed [63:0] square_x_q26=square_x>>>26;
  wire signed [63:0] square_y_q26=square_y>>>26;
  wire signed [63:0] cross_xy_q26=cross_xy>>>26;
  wire signed [31:0] xx2_next=square_x_q26[31:0];
  wire signed [31:0] yy2_next=square_y_q26[31:0];
  wire signed [31:0] xy2_next=cross_xy_q26[31:0];
  wire signed [32:0] r2_next=$signed({xx2_next[31],xx2_next})+
   $signed({yy2_next[31],yy2_next});
  reg signed [31:0] x2,y2,xx2,yy2,xy2,r2_2;

  // E3. Constants have |value| <= 2. Terms are widened before doubling.
  // All four tangential products remain separate until AFTER their shifts.
  wire signed [63:0] k2_r2=K2_Q26*r2_2;
  wire signed [63:0] k2_r2_q26=k2_r2>>>26;
  wire signed [63:0] inner_next={{32{K1_Q26[31]}},K1_Q26}+k2_r2_q26;
  wire signed [39:0] xx40={{8{xx2[31]}},xx2};
  wire signed [39:0] yy40={{8{yy2[31]}},yy2};
  wire signed [39:0] xy40={{8{xy2[31]}},xy2};
  wire signed [39:0] r2_40={{8{r2_2[31]}},r2_2};
  wire signed [39:0] two_xy=xy40<<<1;
  wire signed [39:0] r2_two_xx=r2_40+(xx40<<<1);
  wire signed [39:0] r2_two_yy=r2_40+(yy40<<<1);
  wire signed [71:0] tx_p1=P1_Q26*two_xy,tx_p2=P2_Q26*r2_two_xx;
  wire signed [71:0] ty_p1=P1_Q26*r2_two_yy,ty_p2=P2_Q26*two_xy;
  reg signed [39:0] inner3;
  reg signed [31:0] x3,y3,r2_3;
  reg signed [71:0] tx_p1_3,tx_p2_3,ty_p1_3,ty_p2_3;

  // E4. Worst-case radial magnitude <= 145*S; tangential <= 48*S.
  wire signed [71:0] r2_inner=r2_3*inner3;
  wire signed [71:0] radial_next=72'sd67108864+(r2_inner>>>26);
  wire signed [71:0] tx_next=(tx_p1_3>>>26)+(tx_p2_3>>>26);
  wire signed [71:0] ty_next=(ty_p1_3>>>26)+(ty_p2_3>>>26);
  reg signed [47:0] radial4;
  reg signed [39:0] tx4,ty4;
  reg signed [31:0] x4,y4;

  // E5 / E6. Shift the radial product before adding the tangential result.
  wire signed [79:0] x_radial=x4*radial4,y_radial=y4*radial4;
  reg signed [79:0] x_radial5,y_radial5;
  reg signed [39:0] tx5,ty5;
  wire signed [79:0] xd_next=(x_radial5>>>26)+{{40{tx5[39]}},tx5};
  wire signed [79:0] yd_next=(y_radial5>>>26)+{{40{ty5[39]}},ty5};
  reg signed [47:0] xd6,yd6;

  // E7 / E8. Preserve signed80 until the final Q42 -> Q8 arithmetic shift.
  wire signed [79:0] pixel_x=xd6*FX_Q16,pixel_y=yd6*FY_Q16;
  reg signed [79:0] pixel_x7,pixel_y7;
  wire signed [79:0] cx80={{48{CX_Q16[31]}},CX_Q16};
  wire signed [79:0] cy80={{48{CY_Q16[31]}},CY_Q16};
  wire signed [79:0] sx_next=(pixel_x7+(cx80<<<26))>>>34;
  wire signed [79:0] sy_next=(pixel_y7+(cy80<<<26))>>>34;
  reg signed [39:0] sx8,sy8;
  assign mapped_x8=sx8;assign mapped_y8=sy8;

  always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin
    norm_x0<=0;norm_y0<=0;x1<=0;y1<=0;
    x2<=0;y2<=0;xx2<=0;yy2<=0;xy2<=0;r2_2<=0;
    inner3<=0;x3<=0;y3<=0;r2_3<=0;
    tx_p1_3<=0;tx_p2_3<=0;ty_p1_3<=0;ty_p2_3<=0;
    radial4<=0;tx4<=0;ty4<=0;x4<=0;y4<=0;
    x_radial5<=0;y_radial5<=0;tx5<=0;ty5<=0;
    xd6<=0;yd6<=0;pixel_x7<=0;pixel_y7<=0;sx8<=0;sy8<=0;
   end else begin
    norm_x0<=norm_product_x;norm_y0<=norm_product_y;
    x1<=normalize_error?32'sd0:normalized_x[31:0];
    y1<=normalize_error?32'sd0:normalized_y[31:0];
    x2<=x1;y2<=y1;xx2<=xx2_next;yy2<=yy2_next;xy2<=xy2_next;r2_2<=r2_next[31:0];
    inner3<=inner_next[39:0];x3<=x2;y3<=y2;r2_3<=r2_2;
    tx_p1_3<=tx_p1;tx_p2_3<=tx_p2;ty_p1_3<=ty_p1;ty_p2_3<=ty_p2;
    radial4<=radial_next[47:0];tx4<=tx_next[39:0];ty4<=ty_next[39:0];x4<=x3;y4<=y3;
    x_radial5<=x_radial;y_radial5<=y_radial;tx5<=tx4;ty5<=ty4;
    xd6<=xd_next[47:0];yd6<=yd_next[47:0];
    pixel_x7<=pixel_x;pixel_y7<=pixel_y;sx8<=sx_next[39:0];sy8<=sy_next[39:0];
   end
  end
 end endgenerate
endmodule
