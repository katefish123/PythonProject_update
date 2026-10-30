`timescale 1ns/1ps
`default_nettype none
// UI-clock transaction join: source qualification + write drain + slot publish.
// Input producer must hold each block until accepted and flush aborted tokens
// before starting another capture. Reset together with every memory participant.
module ddr_capture_session #(
 parameter integer SRC_W=1920,SRC_H=1080,OUT_W=640,OUT_H=904,
 parameter integer MEMORY_BYTES=1073741824
)(
 input wire clk,rst_n,capture_start,output wire capture_ready,
 input wire source_done,source_ok,capture_abort,
 input wire block_valid,output wire block_ready,input wire [255:0] block_data,
 input wire [31:0] block_strb,input wire block_last,
 output wire busy,capture_done,capture_ok,
 output wire cmd_valid,input wire cmd_ready,output wire cmd_write,
 output wire [27:0] cmd_addr,output wire [255:0] cmd_wdata,output wire [31:0] cmd_wstrb,
 input wire rsp_valid,rsp_write,mem_fault,read_acquire,read_release,
 output wire latest_valid,output wire [1:0] latest_slot,output wire [31:0] latest_frame_id,
 output wire read_locked,output wire [1:0] read_slot,output wire [31:0] read_frame_id,
 output wire [31:0] result_base0_byte,result_base1_byte,output wire layout_valid
);
 localparam IDLE=0,ALLOC=1,ARM=2,RUN=3,COMMIT=4;
 localparam [63:0] PIXELS=64'd1*SRC_W*SRC_H;
 localparam [63:0] BLOCKS=(PIXELS+7)/8;
 localparam [31:0] LAST_MASK=32'hffffffff >> (((8-(PIXELS%8))%8)*4);
 reg [2:0] state;
 reg bad,rx_finished,wr_finished,wr_ok;
 reg done_reg,ok_reg;
 reg [31:0] blocks_seen;
 wire [31:0] sb0,sb1,sb2,source_bytes,result_bytes;
 wire slots_grant,slots_drop,writing;wire [1:0] write_slot;
 wire writer_ready,writer_block_ready,writer_busy,writer_done,writer_ok;
 wire start_accept=capture_start&&capture_ready;
 wire last_expected=(blocks_seen==BLOCKS-1);
 wire format_bad=(state==RUN)&&block_valid&&
  ((blocks_seen>=BLOCKS)||(block_last!=last_expected)||
   (block_strb!=(last_expected?LAST_MASK:32'hffffffff)));
 wire transaction_bad=bad||capture_abort||mem_fault||format_bad||(source_done&&!source_ok);
 wire [31:0] base_byte=(write_slot==0)?sb0:((write_slot==1)?sb1:sb2);
 assign capture_ready=rst_n&&(state==IDLE)&&layout_valid&&!mem_fault&&!capture_abort;
 assign busy=(state!=IDLE);
 assign capture_done=done_reg;assign capture_ok=ok_reg;
 assign block_ready=(state==RUN)&&!wr_finished&&!transaction_bad&&writer_block_ready;
 ddr_memory_layout #(.SRC_W(SRC_W),.SRC_H(SRC_H),.OUT_W(OUT_W),.OUT_H(OUT_H),
  .MEMORY_BYTES(MEMORY_BYTES)) layout(sb0,sb1,sb2,result_base0_byte,result_base1_byte,
  source_bytes,result_bytes,layout_valid);
 ddr_frame_slots slots(.clk(clk),.rst_n(rst_n),.capture_start(start_accept),
  .write_complete(state==COMMIT),.capture_abort(busy&&transaction_bad),
  .read_acquire(read_acquire),.read_release(read_release),.capture_grant(slots_grant),
  .capture_drop(slots_drop),.writing(writing),.write_slot(write_slot),
  .latest_valid(latest_valid),.latest_slot(latest_slot),.latest_frame_id(latest_frame_id),
  .read_locked(read_locked),.read_slot(read_slot),.read_frame_id(read_frame_id));
 ddr_block_writer writer(.clk(clk),.rst_n(rst_n),
  .frame_start((state==ARM)&&!transaction_bad),.frame_start_ready(writer_ready),
  .frame_base_byte(base_byte),.frame_abort(busy&&transaction_bad),
  .block_valid(block_valid&&(state==RUN)&&!wr_finished&&!transaction_bad),
  .block_ready(writer_block_ready),.block_data(block_data),.block_strb(block_strb),.block_last(block_last),
  .busy(writer_busy),.frame_done(writer_done),.frame_ok(writer_ok),
  .cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_write(cmd_write),.cmd_addr(cmd_addr),
  .cmd_wdata(cmd_wdata),.cmd_wstrb(cmd_wstrb),.rsp_valid(rsp_valid),.rsp_write(rsp_write),.mem_fault(mem_fault));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;bad<=0;rx_finished<=0;wr_finished<=0;wr_ok<=0;blocks_seen<=0;done_reg<=0;ok_reg<=0;
  end else begin
   done_reg<=0;ok_reg<=0;
   if(busy)begin
    if(transaction_bad)bad<=1;
    if(source_done||capture_abort||mem_fault||format_bad)rx_finished<=1;
    if(writer_done)begin
     wr_finished<=1;wr_ok<=writer_ok;
     if(!writer_ok)begin bad<=1;rx_finished<=1;end
    end
    if(block_valid&&block_ready)blocks_seen<=blocks_seen+1'b1;
   end
   case(state)
    IDLE:if(start_accept)begin
     bad<=source_done&&!source_ok;rx_finished<=source_done;
     wr_finished<=0;wr_ok<=0;blocks_seen<=0;state<=ALLOC;
    end
    ALLOC:begin
     if(slots_grant)state<=ARM;
     else if(slots_drop)begin done_reg<=1;state<=IDLE;end
    end
    ARM:begin
     if(transaction_bad)begin wr_finished<=1;wr_ok<=0;state<=RUN;end
     else if(writer_ready)state<=RUN;
    end
    RUN:if(rx_finished&&wr_finished)state<=COMMIT;
    COMMIT:begin
     done_reg<=1;ok_reg<=!transaction_bad&&wr_ok;state<=IDLE;
    end
    default:begin bad<=1;state<=RUN;end
   endcase
  end
 end
endmodule
`default_nettype wire
