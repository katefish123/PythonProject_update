`timescale 1ns/1ps
// Diagnostic fallback for a missing VS signal. Not an interlace converter.
module hdmi_vs_recover #(parameter VS_TIMEOUT_LINES=2250)(input clk,reset_n,de,hs,vs_in,output vs_out);
reg hs_prev,vs_prev,vs_seen,de_seen,generated_vs;
reg [15:0] line_count,line_period;
// Count received lines, so loss detection follows the incoming frame rate.
// Zero disables expiry. Clock/HS loss must be handled outside this clock domain.
localparam VS_AGE_WIDTH=(VS_TIMEOUT_LINES<2)?1:$clog2(VS_TIMEOUT_LINES+1);
reg [VS_AGE_WIDTH-1:0] vs_age;
reg [23:0] gap;
wire [23:0] start_gap={6'd0,line_period,2'b00};
wire [23:0] stop_gap={5'd0,line_period,3'b000}+line_period; // 9 line periods
always @(posedge clk or negedge reset_n)begin
 if(!reset_n)begin hs_prev<=0;vs_prev<=0;vs_seen<=0;de_seen<=0;generated_vs<=0;line_count<=0;line_period<=0;gap<=0;vs_age<=0;end
 else begin
  hs_prev<=hs;vs_prev<=vs_in;
  if(vs_in!=vs_prev)begin vs_seen<=1;vs_age<=0;end
  else if(VS_TIMEOUT_LINES!=0 && vs_seen && hs && !hs_prev)begin
   if(vs_age==VS_TIMEOUT_LINES-1)begin vs_seen<=0;vs_age<=0;end
   else vs_age<=vs_age+1'b1;
  end
  line_count<=line_count+1'b1;
  if(hs && !hs_prev)begin line_period<=line_count+1'b1;line_count<=0;end
  if(de)begin gap<=0;generated_vs<=0;de_seen<=1;end
  else begin
   if(gap!=24'hffffff)gap<=gap+1'b1;
   if(de_seen && line_period!=0 && gap==start_gap)generated_vs<=1;
   if(line_period!=0 && gap==stop_gap)generated_vs<=0;
  end
 end
end
assign vs_out=vs_seen ? vs_in : generated_vs;
endmodule
