`timescale 1ns/1ps
`default_nettype none
// Synthetic-only complete K/lens/H bundle; no physical calibration implied.
module lens_profile_bank(input wire clk,rst_n,cfg_begin,cfg_write,cfg_seal,frame_start,
 input wire[4:0]cfg_index,input wire[63:0]cfg_data,
 input wire[12:0]expected_width,expected_height,input wire[31:0]expected_mode,
 output reg cfg_error,pending_valid,output wire active_valid,output reg[1471:0]active_words);
 localparam signed[63:0]ONE=64'sd1073741824,MAX_FOCAL=64'sd70368744177664;
 reg signed[63:0]pending[0:22];reg[22:0]written;reg loading,load_error;
 reg active_installed;
 wire pending_runtime_match=pending[17]==$signed({51'd0,expected_width})&&pending[18]==$signed({51'd0,expected_height})&&pending[21]==$signed({32'd0,expected_mode});
 assign active_valid=active_installed&&active_words[17*64+:64]=={51'd0,expected_width}
 &&active_words[18*64+:64]=={51'd0,expected_height}&&active_words[21*64+:64]=={32'd0,expected_mode};
 reg valid;integer i;
 always @*begin
 valid=&written&&!load_error;
 valid=valid&&pending[17]>=2&&pending[17]<=4096&&pending[18]>=2&&pending[18]<=4096
 &&pending[17]==$signed({51'd0,expected_width})&&pending[18]==$signed({51'd0,expected_height});
 valid=valid&&pending[0]>=ONE&&pending[0]<=MAX_FOCAL&&pending[1]>=ONE&&pending[1]<=MAX_FOCAL;
 valid=valid&&pending[2]>=0&&pending[2]<=((pending[17]-1)<<<30)
 &&pending[3]>=0&&pending[3]<=((pending[18]-1)<<<30);
 valid=valid&&pending[4]>=-ONE&&pending[4]<=ONE&&pending[5]>=-ONE&&pending[5]<=ONE
 &&pending[6]>=-(ONE>>>2)&&pending[6]<=(ONE>>>2)&&pending[7]>=-(ONE>>>2)&&pending[7]<=(ONE>>>2);
 for(integer n=8;n<17;n=n+1)valid=valid&&pending[n]>=-MAX_FOCAL&&pending[n]<=MAX_FOCAL;
 valid=valid&&pending[19]>0&&pending[19]<=64'shffffffff&&pending[20]>0&&pending[20]<=64'shffffffff
 &&pending[21]==$signed({32'd0,expected_mode})&&pending[22]==1;
 end
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin cfg_error<=0;pending_valid<=0;active_installed<=0;active_words<=0;written<=0;loading<=0;load_error<=0;
 for(i=0;i<23;i=i+1)pending[i]<=0;end
 else begin
 cfg_error<=0;
 if(frame_start&&pending_valid)begin
 if(pending_runtime_match)begin
 for(i=0;i<23;i=i+1)active_words[i*64+:64]<=pending[i];
 active_installed<=1;end else cfg_error<=1;
 pending_valid<=0;end
 if((cfg_begin&&cfg_write)||(cfg_begin&&cfg_seal)||(cfg_write&&cfg_seal))begin cfg_error<=1;load_error<=1;end
 else if(pending_valid&&(cfg_begin||cfg_write||cfg_seal))cfg_error<=1;
 else if(cfg_begin)begin written<=0;loading<=1;load_error<=0;end
 else if(cfg_write)begin
 if(!loading||cfg_index>=23)begin cfg_error<=1;load_error<=1;end
 else begin pending[cfg_index]<=cfg_data;written[cfg_index]<=1;end end
 else if(cfg_seal)begin
 loading<=0;if(!loading||!valid)cfg_error<=1;else pending_valid<=1;
 end end end
endmodule
`default_nettype wire
