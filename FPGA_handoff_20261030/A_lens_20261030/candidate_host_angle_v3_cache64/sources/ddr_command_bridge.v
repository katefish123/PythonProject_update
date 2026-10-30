`timescale 1ns/1ps
`default_nettype none
// One outstanding bundled-data transaction. Request/response payloads are held
// unchanged until their toggle acknowledgements cross the opposite domain.
// Both resets must assert together with the DDR transaction engine reset.
module ddr_command_bridge(
 input wire src_clk,src_rst_n,dst_clk,dst_rst_n,
 input wire src_cmd_valid,output wire src_cmd_ready,
 input wire src_cmd_write,input wire [27:0] src_cmd_addr,
 input wire [255:0] src_cmd_wdata,input wire [31:0] src_cmd_wstrb,
 output reg src_rsp_valid,src_rsp_write,output reg [255:0] src_rsp_rdata,
 output reg dst_cmd_valid,input wire dst_cmd_ready,
 output reg dst_cmd_write,output reg [27:0] dst_cmd_addr,
 output reg [255:0] dst_cmd_wdata,output reg [31:0] dst_cmd_wstrb,
 input wire dst_rsp_valid,dst_rsp_write,input wire [255:0] dst_rsp_rdata
);
 reg request_toggle,response_toggle,pending;
 reg held_write;reg [27:0] held_addr;
 reg [255:0] held_wdata,held_rdata;reg [31:0] held_wstrb;
 reg held_rsp_write;
 (* ASYNC_REG="TRUE" *) reg [2:0] req_sync,rsp_sync;
 reg [2:0] state;
 localparam IDLE=0,SETTLE=1,SEND=2,WAIT_RSP=3;
 reg active_token;
 assign src_cmd_ready=src_rst_n&&!pending;
 always @(posedge src_clk or negedge src_rst_n)begin
  if(!src_rst_n)begin
   request_toggle<=0;pending<=0;held_write<=0;held_addr<=0;held_wdata<=0;held_wstrb<=0;
   rsp_sync<=0;src_rsp_valid<=0;src_rsp_write<=0;src_rsp_rdata<=0;
  end else begin
   rsp_sync<={rsp_sync[1:0],response_toggle};src_rsp_valid<=0;
   if(src_cmd_valid&&src_cmd_ready)begin
    held_write<=src_cmd_write;held_addr<=src_cmd_addr;
    held_wdata<=src_cmd_wdata;held_wstrb<=src_cmd_wstrb;
    pending<=1;request_toggle<=~request_toggle;
   end
   if(pending&&rsp_sync[2]==request_toggle)begin
    src_rsp_valid<=1;src_rsp_write<=held_rsp_write;src_rsp_rdata<=held_rdata;pending<=0;
   end
  end
 end
 always @(posedge dst_clk or negedge dst_rst_n)begin
  if(!dst_rst_n)begin
   req_sync<=0;response_toggle<=0;state<=IDLE;active_token<=0;
   held_rsp_write<=0;held_rdata<=0;dst_cmd_valid<=0;
   dst_cmd_write<=0;dst_cmd_addr<=0;dst_cmd_wdata<=0;dst_cmd_wstrb<=0;
  end else begin
   req_sync<={req_sync[1:0],request_toggle};
   case(state)
    IDLE:if(req_sync[2]!=response_toggle)begin active_token<=req_sync[2];state<=SETTLE;end
    SETTLE:begin
     dst_cmd_write<=held_write;dst_cmd_addr<=held_addr;
     dst_cmd_wdata<=held_wdata;dst_cmd_wstrb<=held_wstrb;
     dst_cmd_valid<=1;state<=SEND;
    end
    SEND:if(dst_cmd_valid&&dst_cmd_ready)begin
     dst_cmd_valid<=0;
     if(dst_rsp_valid)begin
      held_rsp_write<=dst_rsp_write;held_rdata<=dst_rsp_rdata;
      response_toggle<=active_token;state<=IDLE;
     end else state<=WAIT_RSP;
    end
    WAIT_RSP:if(dst_rsp_valid)begin
     held_rsp_write<=dst_rsp_write;held_rdata<=dst_rsp_rdata;
     response_toggle<=active_token;state<=IDLE;
    end
    default:begin dst_cmd_valid<=0;state<=IDLE;end
   endcase
  end
 end
endmodule
`default_nettype wire
