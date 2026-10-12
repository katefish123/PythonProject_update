`timescale 1ns/1ps
// Bundled-data request/acknowledge transfer. Source holds data until next request.
module cdc_snapshot #(parameter WIDTH=32)(
 input src_clk,src_reset_n,input [WIDTH-1:0] src_data,
 input dst_clk,dst_reset_n,request,
 output reg [WIDTH-1:0] dst_data,output reg valid,output reg busy);
reg request_toggle,ack_toggle;
reg request_meta,request_sync,ack_meta,ack_sync;
reg [WIDTH-1:0] held_data;
always @(posedge src_clk or negedge src_reset_n)begin
 if(!src_reset_n)begin request_meta<=0;request_sync<=0;ack_toggle<=0;held_data<=0;end
 else begin
  request_meta<=request_toggle;request_sync<=request_meta;
  if(request_sync!=ack_toggle)begin held_data<=src_data;ack_toggle<=request_sync;end
 end
end
always @(posedge dst_clk or negedge dst_reset_n)begin
 if(!dst_reset_n)begin request_toggle<=0;ack_meta<=0;ack_sync<=0;dst_data<=0;valid<=0;busy<=0;end
 else begin
  ack_meta<=ack_toggle;ack_sync<=ack_meta;valid<=0;
  if(request && !busy)begin request_toggle<=!request_toggle;busy<=1;end
  else if(busy && ack_sync==request_toggle)begin dst_data<=held_data;valid<=1;busy<=0;end
 end
end
endmodule
