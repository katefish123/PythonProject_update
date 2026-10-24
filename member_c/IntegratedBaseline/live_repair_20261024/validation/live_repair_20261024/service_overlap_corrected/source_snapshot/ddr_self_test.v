`timescale 1ns/1ps
`default_nettype none
// Small destructive test in a reserved region, before video traffic is enabled.
// Tests every bit of all eight 32-bit words per beat, not just the RGB bytes.
module ddr_self_test #(
 parameter BEATS=256,parameter [27:0] BASE=28'h03f0000
)(
 input wire clk,rst_n,enabled,
 output reg passed,failed,
 output wire cmd_valid,input wire cmd_ready,
 output wire cmd_write,output wire [27:0] cmd_addr,
 output reg [255:0] cmd_wdata,output wire [31:0] cmd_wstrb,
 input wire rsp_valid,rsp_write,input wire [255:0] rsp_rdata
);
 localparam IDLE=0,SEND_WRITE=1,WAIT_WRITE=2,SEND_READ=3,WAIT_READ=4,DONE=5,CHECK_READ=6;
 reg [2:0] state;reg [23:0] index;
 integer lane;reg [7:0] lane_match;
 function [31:0] pattern;
  input [23:0] beat;input integer n;
  begin pattern=32'h5a3cc3a5^(beat*32'h00010001)^(n*32'h01010101);end
 endfunction
 always @*begin
  for(lane=0;lane<8;lane=lane+1)begin
   cmd_wdata[lane*32+:32]=pattern(index,lane);
  end
 end
 assign cmd_valid=state==SEND_WRITE||state==SEND_READ;
 assign cmd_write=state==SEND_WRITE;
 assign cmd_addr=BASE+{1'd0,index,3'b000};
 assign cmd_wstrb=32'hffffffff;
 integer j;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;index<=0;passed<=0;failed<=0;lane_match<=0;end
  else case(state)
   IDLE:if(enabled)state<=SEND_WRITE;
   SEND_WRITE:if(cmd_ready)state<=WAIT_WRITE;
   WAIT_WRITE:if(rsp_valid)begin
    if(!rsp_write)begin failed<=1;state<=DONE;end
    else if(index==BEATS-1)begin index<=0;state<=SEND_READ;end
    else begin index<=index+1;state<=SEND_WRITE;end
   end
   SEND_READ:if(cmd_ready)state<=WAIT_READ;
   WAIT_READ:if(rsp_valid)begin
    if(rsp_write)begin failed<=1;state<=DONE;end
    else begin
     // Capture eight independent comparisons; never reduce a native response
     // directly into the global selftest status in the same UI cycle.
     for(j=0;j<8;j=j+1)lane_match[j]<=(rsp_rdata[j*32+:32]===pattern(index,j));
     state<=CHECK_READ;
    end
   end
   CHECK_READ:begin
    if(!(&lane_match))failed<=1;
    if(index==BEATS-1)begin passed<=!failed&&(&lane_match);state<=DONE;end
    else begin index<=index+1;state<=SEND_READ;end
   end
   DONE:if(failed)passed<=0;
   default:begin failed<=1;state<=DONE;end
  endcase
 end
endmodule
`default_nettype wire
