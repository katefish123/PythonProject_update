// Nonnegative ratio, UQ12.8 by default. One result/clock, fixed latency.
// Integer stages subtract shifted denominator; fraction stages double remainder.
// The valid envelope is numerator/denominator < 2^INT_BITS.
module scaled_div_pipe #(
 parameter WIDTH=48, INT_BITS=12, FRAC_BITS=8, TAG_W=25
)(
 input wire clk,rst_n,in_valid,
 input wire [WIDTH-1:0] numerator,denominator,
 input wire [TAG_W-1:0] in_tag,
 output wire out_valid,out_error,
 output wire [INT_BITS+FRAC_BITS-1:0] quotient,
 output wire [TAG_W-1:0] out_tag
);
 localparam N=INT_BITS+FRAC_BITS;
 localparam EXT=WIDTH+INT_BITS+1;
 reg [WIDTH-1:0] rem[0:N], den[0:N];
 reg [N-1:0] q[0:N];
 reg [TAG_W-1:0] tag[0:N];
 reg [N:0] valid,err;
 wire [EXT-1:0] n_ext={{(EXT-WIDTH){1'b0}},numerator};
 wire [EXT-1:0] d_ext={{(EXT-WIDTH){1'b0}},denominator};
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin valid[0]<=0;err[0]<=0;rem[0]<=0;den[0]<=1;q[0]<=0;tag[0]<=0;end
  else begin
   valid[0]<=in_valid;err[0]<=denominator==0 || n_ext >= (d_ext << INT_BITS);
   rem[0]<=numerator;den[0]<=denominator;q[0]<=0;tag[0]<=in_tag;
  end
 end
 genvar i;
 generate for(i=0;i<N;i=i+1) begin: stage
  wire [EXT-1:0] r_ext={{(EXT-WIDTH){1'b0}},rem[i]};
  wire [EXT-1:0] den_ext={{(EXT-WIDTH){1'b0}},den[i]};
  wire [EXT-1:0] trial = i<INT_BITS ? r_ext : (r_ext << 1);
  wire [EXT-1:0] subtrahend;
  if(i<INT_BITS) begin: integer_bit
   assign subtrahend=den_ext << (INT_BITS-1-i);
  end else begin: fractional_bit
   assign subtrahend=den_ext;
  end
  wire ge=trial>=subtrahend;
  wire [EXT-1:0] next_rem=ge ? trial-subtrahend : trial;
  always @(posedge clk or negedge rst_n) begin
   if(!rst_n) begin valid[i+1]<=0;err[i+1]<=0;rem[i+1]<=0;den[i+1]<=1;q[i+1]<=0;tag[i+1]<=0;end
   else begin
    valid[i+1]<=valid[i];err[i+1]<=err[i];rem[i+1]<=next_rem[WIDTH-1:0];
    den[i+1]<=den[i];q[i+1]<={q[i][N-2:0],ge};tag[i+1]<=tag[i];
   end
  end
 end endgenerate
 assign out_valid=valid[N];assign out_error=valid[N]&&err[N];
 assign quotient=err[N] ? {N{1'b0}} : q[N];assign out_tag=tag[N];
endmodule
