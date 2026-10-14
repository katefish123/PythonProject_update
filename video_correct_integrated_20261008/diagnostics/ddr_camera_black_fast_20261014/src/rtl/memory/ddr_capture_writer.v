`timescale 1ns/1ps
`default_nettype none
// UI-domain FIFO drain and serialized DDR writer. A transaction is acknowledged
// only after RX completion, FIFO quiescence, and every accepted DDR response.
module ddr_capture_writer #(
 parameter SRC_W=640,SRC_H=480,
 parameter EMPTY_QUIET_CYCLES=4
)(
 input wire ui_clk,ui_rst_n,
 input wire request_toggle,rx_complete_toggle,rx_capture_ok,
 output wire fifo_rd_en,input wire fifo_empty,input wire [284:0] fifo_rd_data,input wire fifo_rd_valid,
 output reg cmd_valid,input wire cmd_ready,
 output wire cmd_write,output reg [27:0] cmd_addr,output reg [255:0] cmd_wdata,output wire [31:0] cmd_wstrb,
 input wire rsp_valid,rsp_write,
 output reg complete_toggle,output reg capture_ok
);
 localparam EXPECTED_WORDS=(SRC_W*SRC_H)/8;
 localparam IDLE=0,POP=1,WAIT_FIFO=2,CMD=3,WAIT_RSP=4;
 reg [2:0] state;
 (* ASYNC_REG="TRUE" *) reg [2:0] request_sync,rx_done_sync,rx_ok_sync;
 reg token,frame_bad;
 reg [31:0] packets_seen,packets_written,empty_quiet;
 wire [284:0] packet=fifo_rd_data;
 wire packet_token=packet[284];
 wire [27:0] packet_addr=packet[283:256];
 assign fifo_rd_en=(state==POP)&&!fifo_empty;
 assign cmd_write=1'b1;
 assign cmd_wstrb=32'hffffffff;
 always @(posedge ui_clk or negedge ui_rst_n)begin
  if(!ui_rst_n)begin
   request_sync<=0;rx_done_sync<=0;rx_ok_sync<=0;state<=IDLE;
   token<=0;frame_bad<=0;packets_seen<=0;packets_written<=0;empty_quiet<=0;
   complete_toggle<=0;capture_ok<=0;cmd_valid<=0;cmd_addr<=0;cmd_wdata<=0;
  end else begin
   request_sync<={request_sync[1:0],request_toggle};
   rx_done_sync<={rx_done_sync[1:0],rx_complete_toggle};
   rx_ok_sync<={rx_ok_sync[1:0],rx_capture_ok};
   case(state)
    IDLE:begin
     cmd_valid<=0;
     if(request_sync[2]!=complete_toggle)begin
      token<=request_sync[2];frame_bad<=0;packets_seen<=0;packets_written<=0;empty_quiet<=0;state<=POP;
     end
    end
    POP:begin
     if(!fifo_empty)begin empty_quiet<=0;state<=WAIT_FIFO;end
     else if(rx_done_sync[2]==token)begin
      if(empty_quiet<EMPTY_QUIET_CYCLES)empty_quiet<=empty_quiet+1'b1;
      else begin
       capture_ok<=rx_ok_sync[2]&&!frame_bad&&
         packets_seen==EXPECTED_WORDS&&packets_written==EXPECTED_WORDS;
       complete_toggle<=token;state<=IDLE;
      end
     end else empty_quiet<=0;
    end
    WAIT_FIFO:if(fifo_rd_valid)begin
     if(packet_token!=token)begin
      // Discard stale tokens left across a malformed or reset transaction.
      state<=POP;
     end else begin
      empty_quiet<=0;packets_seen<=packets_seen+1'b1;
      if(packet_addr!={packets_seen[24:0],3'b000}||packets_seen>=EXPECTED_WORDS)begin
       frame_bad<=1;state<=POP;
      end else begin
       cmd_addr<=packet_addr;cmd_wdata<=packet[255:0];cmd_valid<=1;state<=CMD;
      end
     end
    end
    CMD:if(cmd_valid&&cmd_ready)begin
     cmd_valid<=0;
     if(rsp_valid)begin
      if(rsp_write)packets_written<=packets_written+1'b1;else frame_bad<=1;
      state<=POP;
     end else state<=WAIT_RSP;
    end
    WAIT_RSP:if(rsp_valid)begin
     if(rsp_write)packets_written<=packets_written+1'b1;else frame_bad<=1;
     state<=POP;
    end
    default:begin state<=IDLE;cmd_valid<=0;frame_bad<=1;end
   endcase
  end
 end
endmodule
`default_nettype wire
