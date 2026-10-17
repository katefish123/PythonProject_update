`timescale 1ns/1ps
`default_nettype none
// Correctness baseline: signed Q34.30 add/multiply/divide, no wrap/saturation.
// Op0 add,1 multiply,2 divide. Single outstanding operation, done one cycle.
module q30_alu(input wire clk,rst_n,start,input wire[1:0]op,
 input wire signed[63:0]a,b,output wire ready,
 output reg done,error,output reg signed[63:0]value);
 reg busy,negative;reg[7:0]iteration;
 reg[127:0]dividend,divisor,quotient;reg[128:0]remainder;
 reg[128:0]step_rem;reg[127:0]step_quotient;
 reg[127:0]magnitude,rounded;reg signed[127:0]product;
 reg signed[64:0]sum;
 wire[63:0]aa=a[63]?(~a+64'd1):a;
 wire[63:0]bb=b[63]?(~b+64'd1):b;
 assign ready=!busy;
 task finish_magnitude(input[127:0]q,input neg);
 begin
 done<=1;busy<=0;
 if(q>(neg?128'h8000000000000000:128'h7fffffffffffffff))begin error<=1;value<=0;end
 else begin error<=0;value<=neg?(-q[63:0]):q[63:0];end
 end endtask
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin busy<=0;negative<=0;iteration<=0;dividend<=0;divisor<=0;quotient<=0;remainder<=0;done<=0;error<=0;value<=0;end
 else begin
 done<=0;
 if(start&&!busy)begin
 error<=0;
 case(op)
 0:begin sum={a[63],a}+{b[63],b};done<=1;
 if(sum[64]!=sum[63])begin error<=1;value<=0;end else value<=sum[63:0];end
 1:begin product=a*b;magnitude=product[127]?-product:product;
 rounded=magnitude>>30;
 if(magnitude[29:0]>30'h20000000||(magnitude[29:0]==30'h20000000&&rounded[0]))rounded=rounded+1'b1;
 finish_magnitude(rounded,product[127]);end
 2:if(b==0)begin done<=1;error<=1;value<=0;end
 else begin busy<=1;negative<=a[63]^b[63];iteration<=0;
 dividend<={64'd0,aa}<<30;divisor<={64'd0,bb};quotient<=0;remainder<=0;end
 default:begin done<=1;error<=1;value<=0;end
 endcase
 end else if(busy)begin
 step_rem={remainder[127:0],dividend[127]};
 step_quotient=quotient<<1;
 if(step_rem>={1'b0,divisor})begin step_rem=step_rem-{1'b0,divisor};step_quotient[0]=1;end
 remainder<=step_rem;dividend<=dividend<<1;quotient<=step_quotient;
 if(iteration==127)begin
 rounded=step_quotient;
 if((step_rem<<1)>{1'b0,divisor}||((step_rem<<1)=={1'b0,divisor}&&rounded[0]))rounded=rounded+1'b1;
 finish_magnitude(rounded,negative);
 end else iteration<=iteration+1'b1;
 end
 end end
endmodule
`default_nettype wire
