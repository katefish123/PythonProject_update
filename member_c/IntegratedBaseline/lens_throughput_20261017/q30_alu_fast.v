`timescale 1ns/1ps
`default_nettype none
// Bit-exact Q34.30 arithmetic; divide processes only meaningful quotient bits.
module q30_alu_fast(input wire clk,rst_n,start,input wire[1:0]op,
 input wire signed[63:0]a,b,output wire ready,
 output reg done,error,output reg signed[63:0]value);
 reg busy,negative,round_pending;reg[6:0]bit_index;
 reg[93:0]numerator,trial,next_remainder;reg[63:0]divisor;
 reg[64:0]quotient,next_quotient,rounded_div;reg[94:0]difference;
 reg[127:0]magnitude,rounded;
 reg signed[127:0]product;reg signed[64:0]sum;
 reg[127:0]initial_n,initial_d;integer nbits,dbits,shift,i;
 wire[63:0]aa=a[63]?(~a+64'd1):a;
 wire[63:0]bb=b[63]?(~b+64'd1):b;
 assign ready=!busy;
 task finish(input[127:0]q,input neg);
 begin done<=1;busy<=0;
 if(q>(neg?128'h8000000000000000:128'h7fffffffffffffff))begin error<=1;value<=0;end
 else begin error<=0;value<=neg?(-q[63:0]):q[63:0];end
 end endtask
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin busy<=0;negative<=0;round_pending<=0;bit_index<=0;numerator<=0;divisor<=0;trial<=0;quotient<=0;done<=0;error<=0;value<=0;end
 else begin
 done<=0;
 if(start&&!busy)begin
 error<=0;round_pending<=0;
 case(op)
 0:begin sum={a[63],a}+{b[63],b};done<=1;
 if(sum[64]!=sum[63])begin error<=1;value<=0;end else value<=sum[63:0];end
 1:begin product=a*b;magnitude=product[127]?-product:product;rounded=magnitude>>30;
 if(magnitude[29:0]>30'h20000000||(magnitude[29:0]==30'h20000000&&rounded[0]))rounded=rounded+1'b1;
 finish(rounded,product[127]);end
 2:if(b==0)begin done<=1;error<=1;value<=0;end
 else begin
 initial_n={64'd0,aa}<<30;initial_d={64'd0,bb};
 if(initial_n>=(initial_d<<64))begin done<=1;error<=1;value<=0;end
 else begin
 nbits=0;dbits=0;
 for(i=0;i<94;i=i+1)if(initial_n[i])nbits=i+1;
 for(i=0;i<64;i=i+1)if(initial_d[i])dbits=i+1;
 shift=nbits>dbits?nbits-dbits:0;
 numerator<=initial_n[93:0];divisor<=initial_d[63:0];trial<=initial_d<<shift;
 bit_index<=shift;quotient<=0;negative<=a[63]^b[63];busy<=1;
 end end
 default:begin done<=1;error<=1;value<=0;end
 endcase
 end else if(busy&&round_pending)begin
 rounded_div=quotient;
 if((numerator<<1)>divisor||((numerator<<1)==divisor&&rounded_div[0]))rounded_div=rounded_div+1'b1;
 finish({63'd0,rounded_div},negative);round_pending<=0;
 end else if(busy)begin
 next_remainder=numerator;next_quotient=quotient;
 difference={1'b0,numerator}-{1'b0,trial};
 if(!difference[94])begin next_remainder=difference[93:0];next_quotient[bit_index]=1;end
 numerator<=next_remainder;quotient<=next_quotient;trial<=trial>>1;
 if(bit_index==0)round_pending<=1;
 else bit_index<=bit_index-1'b1;
 end
 end end
endmodule
`default_nettype wire
