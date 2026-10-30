// Signed 64-bit quotient, truncation toward zero. INT64_MIN/-1 rejected.
module signed_div_seq (
 input wire clk,rst_n,start,
 input wire signed [63:0] numerator,denominator,
 output wire busy, output wire done,
 output wire error, output wire signed [63:0] quotient
);
 reg negative, overflow;
 wire [63:0] un = numerator[63] ? -numerator : numerator;
 wire [63:0] ud = denominator[63] ? -denominator : denominator;
 wire [63:0] uq;
 wire ue;
 unsigned_div_seq #(.WIDTH(64)) u(clk,rst_n,start,un,ud,busy,done,ue,uq);
 always @(posedge clk or negedge rst_n)
  if (!rst_n) begin negative<=0;overflow<=0;end
  else if (start && !busy) begin
   negative<=numerator[63]^denominator[63];
   overflow<=numerator==64'sh8000000000000000 && denominator==-64'sd1;
  end
 assign error=ue|overflow;
 assign quotient=error ? 64'sd0 : (negative ? -$signed(uq) : $signed(uq));
endmodule
