// RGB888, four neighbors and UQ0.8 fractions. Three registered stages.
module bilinear_interp #(parameter TAG_W=24)(
 input wire clk,rst_n,in_valid,in_inside,
 input wire [23:0] p00,p10,p01,p11,
 input wire [7:0] fx,fy,
 input wire [TAG_W-1:0] in_tag,
 output reg out_valid,output reg [23:0] rgb,
 output reg [TAG_W-1:0] out_tag
);
 wire [8:0] wx=9'd256-{1'b0,fx};
 reg [15:0] top[0:2],bot[0:2];
 reg [23:0] blend[0:2];
 reg [7:0] fy1;
 reg [2:0] valid,inside_pipe;
 reg [TAG_W-1:0] tag1,tag2;
 integer c;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   valid<=0;inside_pipe<=0;fy1<=0;tag1<=0;tag2<=0;out_tag<=0;out_valid<=0;rgb<=0;
   for(c=0;c<3;c=c+1) begin top[c]<=0;bot[c]<=0;blend[c]<=0;end
  end else begin
   valid<={valid[1:0],in_valid};inside_pipe<={inside_pipe[1:0],in_inside};fy1<=fy;tag1<=in_tag;tag2<=tag1;
   for(c=0;c<3;c=c+1) begin
    top[c]<=p00[c*8+:8]*wx+p10[c*8+:8]*{1'b0,fx};
    bot[c]<=p01[c*8+:8]*wx+p11[c*8+:8]*{1'b0,fx};
    blend[c]<=top[c]*(9'd256-{1'b0,fy1})+bot[c]*{1'b0,fy1};
    rgb[c*8+:8]<=valid[1]&&inside_pipe[1] ? blend[c][23:16] : 8'd0;
   end
   out_valid<=valid[1];out_tag<=tag2;
  end
 end
endmodule
