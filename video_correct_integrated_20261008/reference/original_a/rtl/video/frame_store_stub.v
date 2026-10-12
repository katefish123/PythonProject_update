`timescale 1ns/1ps
`default_nettype none
// A-owned placeholder. NO storage, DDR, frame ownership or CDC is implemented.
// Every request returns one black response after one register stage.
// Keep inside/tag/weights intact; missing_storage flags reads we cannot serve.
module frame_store_stub (
 input wire clk, rst_n,
 input wire req_valid, req_inside,
 input wire [23:0] req_tag, addr00, addr10, addr01, addr11,
 input wire [7:0] req_fx, req_fy,
 output reg rsp_valid, rsp_inside,
 output reg [23:0] rsp_tag,
 output reg [7:0] rsp_fx, rsp_fy,
 output wire [23:0] p00, p10, p01, p11,
 output reg missing_storage
);
 assign p00=24'd0; assign p10=24'd0;
 assign p01=24'd0; assign p11=24'd0;
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
   rsp_valid<=0; rsp_inside<=0; rsp_tag<=0;
   rsp_fx<=0; rsp_fy<=0; missing_storage<=0;
  end else begin
   rsp_valid<=req_valid;
   rsp_inside<=req_inside; rsp_tag<=req_tag;
   rsp_fx<=req_fx; rsp_fy<=req_fy;
   if (req_valid && req_inside) missing_storage<=1;
  end
 end
endmodule
`default_nettype wire
