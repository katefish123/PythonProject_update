// Low-rate, all-integer quad -> inverse H. No external CPU is required.
// Coefficients signed 40/F24. Clockwise convex quad in image coordinates.
module homography_solver #(
 parameter SRC_W=640,SRC_H=480,OUT_W=320,OUT_H=452
)(
 input wire clk,rst_n,start,
 input wire [11:0] x0,y0,x1,y1,x2,y2,x3,y3,
 output wire busy, output reg done,error,
 output reg signed [39:0] h00,h01,h02,h10,h11,h12,h20,h21,h22
);
 localparam signed [63:0] SCALE=64'sd16777216;
 localparam signed [63:0] DMIN=64'sd1048576;
 reg signed [63:0] x[0:3],y[0:3];
 reg signed [63:0] gv,kv;
 reg signed [63:0] work[0:7];
 reg [2:0] state;
 integer step,i,k;
 reg div_start;
 reg signed [63:0] div_n,div_d;
 wire div_busy,div_done,div_error;
 wire signed [63:0] div_q;
 signed_div_seq u_div(clk,rst_n,div_start,div_n,div_d,div_busy,div_done,div_error,div_q);
 assign busy=state!=0;
 wire signed [63:0] dx1=x[1]-x[2],dx2=x[3]-x[2],dx3=x[0]-x[1]+x[2]-x[3];
 wire signed [63:0] dy1=y[1]-y[2],dy2=y[3]-y[2],dy3=y[0]-y[1]+y[2]-y[3];
 wire signed [63:0] det=dx1*dy2-dx2*dy1;
 reg valid_quad,valid_h;
 reg signed [63:0] cross_value,den_check;
 always @* begin
  valid_quad=(det>=16||det<=-16);
  cross_value=0;
  for(k=0;k<4;k=k+1) begin
   cross_value=(x[(k+1)%4]-x[k])*(y[(k+2)%4]-y[(k+1)%4]) - (y[(k+1)%4]-y[k])*(x[(k+2)%4]-x[(k+1)%4]);
   if(cross_value<16||x[k]<0||x[k]>=SRC_W||y[k]<0||y[k]>=SRC_H) valid_quad=0;
  end
  valid_h=gv>=-4*SCALE&&gv<=4*SCALE&&kv>=-4*SCALE&&kv<=4*SCALE;
  den_check=0;
  for(k=0;k<8;k=k+1)
   if(work[k] < -64'sd549755813888 || work[k]>64'sd549755813887) valid_h=0;
  for(k=0;k<4;k=k+1) begin
   den_check=work[6]*((k==1||k==2)?(OUT_W-1):0) + work[7]*((k>=2)?(OUT_H-1):0)+SCALE;
   if(den_check<=DMIN) valid_h=0;
  end
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=0;done<=0;error<=0;step<=0;div_start<=0;div_n<=0;div_d<=1;gv<=0;kv<=0;
   h00<=0;h01<=0;h02<=0;h10<=0;h11<=0;h12<=0;h20<=0;h21<=0;h22<=40'sd16777216;
   for(i=0;i<4;i=i+1) begin x[i]<=0;y[i]<=0;end
   for(i=0;i<8;i=i+1) work[i]<=0;
  end else begin
   done<=0;div_start<=0;
   case(state)
    0: if(start) begin
     x[0]<={52'd0,x0};y[0]<={52'd0,y0};x[1]<={52'd0,x1};y[1]<={52'd0,y1};
     x[2]<={52'd0,x2};y[2]<={52'd0,y2};x[3]<={52'd0,x3};y[3]<={52'd0,y3};
     error<=0;state<=1;
    end
    1: if(!valid_quad) begin error<=1;done<=1;state<=0;end
       else begin step<=0;state<=2;end
    2: begin
     case(step)
      0: begin div_n<=(dx3*dy2-dx2*dy3)*SCALE;div_d<=det;end
      1: begin div_n<=(dx1*dy3-dx3*dy1)*SCALE;div_d<=det;end
      2: begin div_n<=(x[1]-x[0])*SCALE+gv*x[1];div_d<=OUT_W-1;end
      3: begin div_n<=(x[3]-x[0])*SCALE+kv*x[3];div_d<=OUT_H-1;end
      4: begin div_n<=(y[1]-y[0])*SCALE+gv*y[1];div_d<=OUT_W-1;end
      5: begin div_n<=(y[3]-y[0])*SCALE+kv*y[3];div_d<=OUT_H-1;end
      6: begin div_n<=gv;div_d<=OUT_W-1;end
      7: begin div_n<=kv;div_d<=OUT_H-1;end
     endcase
     div_start<=1;state<=3;
    end
    3: if(div_done) begin
     if(div_error) begin error<=1;done<=1;state<=0;end
     else begin
      case(step)
       0: gv<=div_q;
       1: kv<=div_q;
       2: work[0]<=div_q;
       3: work[1]<=div_q;
       4: work[3]<=div_q;
       5: work[4]<=div_q;
       6: work[6]<=div_q;
       7: work[7]<=div_q;
      endcase
      work[2]<=x[0]*SCALE;work[5]<=y[0]*SCALE;
      if(step==7) state<=4;else begin step<=step+1;state<=2;end
     end
    end
    4: begin
     if(valid_h) begin
      h00<=work[0][39:0];h01<=work[1][39:0];h02<=work[2][39:0];
      h10<=work[3][39:0];h11<=work[4][39:0];h12<=work[5][39:0];
      h20<=work[6][39:0];h21<=work[7][39:0];h22<=40'sd16777216;
     end else error<=1;
     done<=1;state<=0;
    end
   endcase
  end
 end
endmodule
