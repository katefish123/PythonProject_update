`timescale 1ns/1ps
`default_nettype none
// Display(client2) retains priority; clients0/1 alternate under contention.
// No transaction owner can change before its response retires.
// Engine has exactly one transaction in flight; response ownership is retained
// through its completion, including writes. All ports belong to clk.
module ddr_arbiter3_turnaround #(parameter BALANCE_C01=0)(
 input wire clk,rst_n,enabled,
 input wire c0_valid,c0_write,input wire [27:0] c0_addr,
 input wire [255:0] c0_wdata,input wire [31:0] c0_wstrb,
 output wire c0_ready,c0_rsp_valid,c0_rsp_write,output wire [255:0] c0_rdata,
 input wire c1_valid,c1_write,input wire [27:0] c1_addr,
 input wire [255:0] c1_wdata,input wire [31:0] c1_wstrb,
 output wire c1_ready,c1_rsp_valid,c1_rsp_write,output wire [255:0] c1_rdata,
 input wire c2_valid,c2_write,input wire [27:0] c2_addr,
 input wire [255:0] c2_wdata,input wire [31:0] c2_wstrb,
 output wire c2_ready,c2_rsp_valid,c2_rsp_write,output wire [255:0] c2_rdata,
 output wire cmd_valid,cmd_write,output wire [27:0] cmd_addr,
 output wire [255:0] cmd_wdata,output wire [31:0] cmd_wstrb,
 input wire cmd_ready,rsp_valid,rsp_write,input wire [255:0] rsp_rdata
);
 reg active;reg [1:0] owner;reg next_client;
 wire [1:0] grant=c2_valid?2'd2:(BALANCE_C01&&c0_valid&&c1_valid)?{1'b0,next_client}:c1_valid?2'd1:2'd0;
 assign cmd_valid=rst_n&&enabled&&(!active||rsp_valid)&&(c0_valid||c1_valid||c2_valid);
 assign cmd_write=grant==2?c2_write:grant==1?c1_write:c0_write;
 assign cmd_addr=grant==2?c2_addr:grant==1?c1_addr:c0_addr;
 assign cmd_wdata=grant==2?c2_wdata:grant==1?c1_wdata:c0_wdata;
 assign cmd_wstrb=grant==2?c2_wstrb:grant==1?c1_wstrb:c0_wstrb;
 assign c0_ready=cmd_valid&&cmd_ready&&grant==0;
 assign c1_ready=cmd_valid&&cmd_ready&&grant==1;
 assign c2_ready=cmd_valid&&cmd_ready&&grant==2;
 assign c0_rsp_valid=active&&owner==0&&rsp_valid;
 assign c1_rsp_valid=active&&owner==1&&rsp_valid;
 assign c2_rsp_valid=active&&owner==2&&rsp_valid;
 assign c0_rsp_write=rsp_write;assign c1_rsp_write=rsp_write;assign c2_rsp_write=rsp_write;
 assign c0_rdata=rsp_rdata;assign c1_rdata=rsp_rdata;assign c2_rdata=rsp_rdata;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin active<=0;owner<=0;next_client<=0;end
  else begin
   if(cmd_valid&&cmd_ready)begin active<=1;owner<=grant;if(grant!=2)next_client<=!grant[0];end
   if(active&&rsp_valid&&!(cmd_valid&&cmd_ready))active<=0;
  end
 end
endmodule
`default_nettype wire
