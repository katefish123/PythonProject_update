`timescale 1ns/1ps
`default_nettype none
// Exact frame-specific component mask, never a bounding-box/black-threshold erase.
module source_marker_clean(input wire clk,rst_n,in_valid,output wire in_ready,
 input wire markers_enabled,mask_valid,input wire[31:0]frame_id,version,mask_frame_id,mask_version,in_tag,
 input wire[3:0]marker_hit,input wire[23:0]background,input wire[95:0]pixels,
 output reg out_valid,input wire out_ready,output reg out_error,
 output reg[95:0]out_pixels,output reg[31:0]out_tag,out_frame_id,out_version);
 wire association_ok=mask_valid&&mask_frame_id==frame_id&&mask_version==version;
 assign in_ready=!out_valid||out_ready;
 integer i;
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin out_valid<=0;out_error<=0;out_pixels<=0;out_tag<=0;out_frame_id<=0;out_version<=0;end
 else if(in_ready)begin
 out_valid<=in_valid;
 if(in_valid)begin
 out_error<=markers_enabled&&!association_ok;
 for(i=0;i<4;i=i+1)out_pixels[i*24+:24]<=markers_enabled&&association_ok&&marker_hit[i]?background:pixels[i*24+:24];
 out_tag<=in_tag;out_frame_id<=frame_id;out_version<=version;
 end end end
endmodule
`default_nettype wire
