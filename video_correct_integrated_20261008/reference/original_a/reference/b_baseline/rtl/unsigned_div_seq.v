// One unsigned restoring division at a time. WIDTH cycles after launch.
module unsigned_div_seq #(parameter WIDTH=64)(
 input wire clk, rst_n, start,
 input wire [WIDTH-1:0] numerator, denominator,
 output reg busy, done, error,
 output reg [WIDTH-1:0] quotient
);
 reg [WIDTH-1:0] q, den;
 reg [WIDTH:0] rem;
 integer count;
 wire [WIDTH:0] trial = {rem[WIDTH-1:0],q[WIDTH-1]};
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
   busy<=0;done<=0;error<=0;quotient<=0;q<=0;den<=0;rem<=0;count<=0;
  end else begin
   done<=0;
   if (start && !busy) begin
    error<=denominator==0;
    if (denominator==0) begin quotient<=0;done<=1;end
    else begin busy<=1;q<=numerator;den<=denominator;rem<=0;count<=WIDTH;end
   end else if (busy) begin
    if (trial >= {1'b0,den}) begin
     rem<=trial-{1'b0,den};q<={q[WIDTH-2:0],1'b1};
    end else begin rem<=trial;q<={q[WIDTH-2:0],1'b0};end
    count<=count-1;
    if (count==1) begin
     quotient<={q[WIDTH-2:0],(trial >= {1'b0,den})};busy<=0;done<=1;
    end
   end
  end
 end
endmodule
