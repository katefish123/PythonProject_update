`timescale 1ns/1ps
`default_nettype none
// UI-domain FIFO drain and serialized DDR writer. A transaction is acknowledged
// only after RX completion, FIFO quiescence, and every accepted DDR response.
module ddr_capture_writer #(
 parameter SRC_W=640,SRC_H=480,
 parameter EMPTY_QUIET_CYCLES=4,parameter BURST_BEATS=1
)(
 input wire ui_clk,ui_rst_n,
 input wire request_toggle,rx_complete_toggle,rx_capture_ok,input wire[3:0]rx_failure_reason,
 output wire fifo_rd_en,input wire fifo_empty,input wire [284:0] fifo_rd_data,input wire fifo_rd_valid,
 output wire cmd_valid,input wire cmd_ready,
 output wire[2047:0]cmd_burst_data,output wire cmd_write,output wire [27:0] cmd_addr,output wire [255:0] cmd_wdata,output wire [31:0] cmd_wstrb,
 input wire rsp_valid,rsp_write,
 output reg complete_toggle,output reg capture_ok,output reg[3:0]failure_reason
);
 generate if(BURST_BEATS==1)begin:single
 assign cmd_burst_data={1792'd0,cmd_wdata};
 localparam EXPECTED_WORDS=(SRC_W*SRC_H)/8;
 localparam IDLE=0,POP=1,CMD=3,WAIT_RSP=4;
 reg [2:0] state;
 (* ASYNC_REG="TRUE" *) reg [2:0] request_sync,rx_done_sync,rx_ok_sync;
 reg token,frame_bad;
 (* ASYNC_REG="TRUE" *)reg[3:0]reason_q0,reason_q1,reason_q2;
 reg [31:0] packets_seen,packets_written,empty_quiet;
 reg pop_pending,buffer_valid;
 reg [284:0] packet_buffer;
 reg cmd_valid_hold;reg[27:0]cmd_addr_hold;reg[255:0]cmd_data_hold;
 wire packet_token=packet_buffer[284];
 wire [27:0] packet_addr=packet_buffer[283:256];
 wire refill=(state==WAIT_RSP)&&rsp_valid&&buffer_valid&&packet_token==token&&
   packet_addr=={packets_seen[24:0],3'b000}&&packets_seen<EXPECTED_WORDS;
 assign cmd_valid=cmd_valid_hold||refill;
 assign cmd_addr=refill?packet_addr:cmd_addr_hold;
 assign cmd_wdata=refill?packet_buffer[255:0]:cmd_data_hold;
 // Prefetch one packet while the previous command waits for its DDR response.
 // The active command registers stay stable through command acceptance.
 assign fifo_rd_en=(state!=IDLE)&&!fifo_empty&&!pop_pending&&!buffer_valid;
 assign cmd_write=1'b1;
 assign cmd_wstrb=32'hffffffff;
 task consume_packet;
  begin
   buffer_valid<=0;empty_quiet<=0;
   if(packet_token!=token)state<=POP;
   else begin
    packets_seen<=packets_seen+1'b1;
    if(packet_addr!={packets_seen[24:0],3'b000}||packets_seen>=EXPECTED_WORDS)begin
     frame_bad<=1;state<=POP;
    end else begin
     cmd_addr_hold<=packet_addr;cmd_data_hold<=packet_buffer[255:0];cmd_valid_hold<=1;state<=CMD;
    end
   end
  end
 endtask
 always @(posedge ui_clk or negedge ui_rst_n)begin
  if(!ui_rst_n)begin
   failure_reason<=0;reason_q0<=0;reason_q1<=0;reason_q2<=0;request_sync<=0;rx_done_sync<=0;rx_ok_sync<=0;state<=IDLE;
   token<=0;frame_bad<=0;packets_seen<=0;packets_written<=0;empty_quiet<=0;
   complete_toggle<=0;capture_ok<=0;cmd_valid_hold<=0;cmd_addr_hold<=0;cmd_data_hold<=0;
   pop_pending<=0;buffer_valid<=0;packet_buffer<=0;
  end else begin
   reason_q0<=rx_failure_reason;reason_q1<=reason_q0;reason_q2<=reason_q1;
   request_sync<={request_sync[1:0],request_toggle};
   rx_done_sync<={rx_done_sync[1:0],rx_complete_toggle};
   rx_ok_sync<={rx_ok_sync[1:0],rx_capture_ok};
   if(fifo_rd_en)pop_pending<=1;
   if(fifo_rd_valid&&pop_pending)begin
    packet_buffer<=fifo_rd_data;buffer_valid<=1;pop_pending<=0;
   end
   case(state)
    IDLE:begin
     cmd_valid_hold<=0;
     if(request_sync[2]!=complete_toggle)begin
      failure_reason<=0;token<=request_sync[2];frame_bad<=0;packets_seen<=0;packets_written<=0;empty_quiet<=0;state<=POP;
     end
    end
    POP:begin
     if(buffer_valid)consume_packet;
     else if(fifo_empty&&!pop_pending&&!fifo_rd_valid&&rx_done_sync[2]==token)begin
      if(empty_quiet<EMPTY_QUIET_CYCLES)empty_quiet<=empty_quiet+1'b1;
      else begin
       capture_ok<=rx_ok_sync[2]&&!frame_bad&&packets_seen==EXPECTED_WORDS&&packets_written==EXPECTED_WORDS;
       failure_reason<=!rx_ok_sync[2]?reason_q2:frame_bad?4'd14:
         (packets_seen!=EXPECTED_WORDS||packets_written!=EXPECTED_WORDS)?4'd15:4'd0;
       complete_toggle<=token;state<=IDLE;
      end
     end else empty_quiet<=0;
    end
    CMD:if(cmd_valid&&cmd_ready)begin
     cmd_valid_hold<=0;
     if(rsp_valid)begin
      if(rsp_write)packets_written<=packets_written+1'b1;else frame_bad<=1;
      state<=POP;
     end else state<=WAIT_RSP;
    end
    WAIT_RSP:if(rsp_valid)begin
     if(rsp_write)packets_written<=packets_written+1'b1;else frame_bad<=1;
     // Retire ownership before the next command handshake, without a FIFO gap.
     if(buffer_valid)begin
      consume_packet;
      if(refill&&cmd_ready)begin cmd_valid_hold<=0;state<=WAIT_RSP;end
     end else state<=POP;
    end
    default:begin state<=IDLE;cmd_valid_hold<=0;frame_bad<=1;pop_pending<=0;buffer_valid<=0;end
   endcase
  end
 end
 end else begin:batched

 localparam EXPECTED_WORDS=(SRC_W*SRC_H)/8;
 (* ASYNC_REG="TRUE" *)reg[2:0]request_sync,done_sync,ok_sync;
 (* ASYNC_REG="TRUE" *)reg[3:0]reason0,reason1,reason2;
 reg active,token,frame_bad,pop_pending,waiting,valid_hold;
 reg[31:0]seen,written,quiet;
 reg[3:0]fill_count;
 reg[27:0]assembly_addr,address_hold;
 reg[2047:0]assembly,data_hold;
 wire packet_token=fifo_rd_data[284];wire[27:0]packet_addr=fifo_rd_data[283:256];
 assign fifo_rd_en=active&&!fifo_empty&&!pop_pending&&fill_count<BURST_BEATS;
 assign cmd_valid=valid_hold;assign cmd_addr=address_hold;
 assign cmd_wdata=data_hold[255:0];assign cmd_burst_data=data_hold;
 assign cmd_write=1'b1;assign cmd_wstrb=32'hffffffff;
 always @(posedge ui_clk or negedge ui_rst_n)begin
  if(!ui_rst_n)begin
   request_sync<=0;done_sync<=0;ok_sync<=0;reason0<=0;reason1<=0;reason2<=0;
   active<=0;token<=0;frame_bad<=0;pop_pending<=0;waiting<=0;valid_hold<=0;
   seen<=0;written<=0;quiet<=0;fill_count<=0;assembly_addr<=0;address_hold<=0;
   assembly<=0;data_hold<=0;complete_toggle<=0;capture_ok<=0;failure_reason<=0;
  end else begin
   request_sync<={request_sync[1:0],request_toggle};done_sync<={done_sync[1:0],rx_complete_toggle};ok_sync<={ok_sync[1:0],rx_capture_ok};
   reason0<=rx_failure_reason;reason1<=reason0;reason2<=reason1;
   if(!active)begin
    if(request_sync[2]!=complete_toggle)begin
     active<=1;token<=request_sync[2];frame_bad<=0;seen<=0;written<=0;quiet<=0;
     fill_count<=0;pop_pending<=0;waiting<=0;valid_hold<=0;capture_ok<=0;failure_reason<=0;
    end
   end else begin
    if(fifo_rd_en)pop_pending<=1;
    if(fifo_rd_valid&&pop_pending)begin
     pop_pending<=0;quiet<=0;
     if(packet_token==token)begin
      seen<=seen+1;
      if(packet_addr!={seen[24:0],3'b0}||seen>=EXPECTED_WORDS)begin
       frame_bad<=1;fill_count<=0;
      end else if(!frame_bad)begin
       if(fill_count==0)assembly_addr<=packet_addr;
       assembly[fill_count*256+:256]<=fifo_rd_data[255:0];fill_count<=fill_count+1;
      end
     end
    end
    if(valid_hold&&cmd_ready)begin
     valid_hold<=0;
     if(rsp_valid)begin if(rsp_write)written<=written+BURST_BEATS;else frame_bad<=1;end
     else waiting<=1;
    end
    if(waiting&&rsp_valid)begin
     waiting<=0;if(rsp_write)written<=written+BURST_BEATS;else frame_bad<=1;
    end
    // The first beat and full payload stay immutable until the engine accepts
    // this command. Its one response means every beat actually reached DDR.
    if(fill_count==BURST_BEATS&&!valid_hold&&(!waiting||rsp_valid))begin
     if(!frame_bad)begin address_hold<=assembly_addr;data_hold<=assembly;valid_hold<=1;end
     fill_count<=0;
    end
    if(frame_bad&&fill_count!=0)fill_count<=0;
    if(fifo_empty&&!pop_pending&&!fifo_rd_valid&&!valid_hold&&!waiting&&done_sync[2]==token)begin
     if(fill_count!=0&&fill_count<BURST_BEATS)begin fill_count<=0;frame_bad<=1;quiet<=0;end
     else if(fill_count==0)begin
      if(quiet<EMPTY_QUIET_CYCLES)quiet<=quiet+1;
      else begin
       capture_ok<=ok_sync[2]&&!frame_bad&&seen==EXPECTED_WORDS&&written==EXPECTED_WORDS;
       failure_reason<=!ok_sync[2]?reason2:frame_bad?4'd14:(seen!=EXPECTED_WORDS||written!=EXPECTED_WORDS)?4'd15:4'd0;
       complete_toggle<=token;active<=0;
      end
     end
    end else quiet<=0;
   end
  end
 end

 end endgenerate
endmodule
`default_nettype wire
