`timescale 1ns/1ps
`default_nettype none
// Same-clock block stream to A's single-command/single-response memory port.
// Reset together with the memory engine; an abort never releases an accepted
// command until its response arrives. No timeout can safely undo a DDR write.
module ddr_block_writer(
 input wire clk,rst_n,frame_start,output wire frame_start_ready,
 input wire [31:0] frame_base_byte,input wire frame_abort,
 input wire block_valid,output wire block_ready,input wire [255:0] block_data,
 input wire [31:0] block_strb,input wire block_last,
 output wire busy,output reg frame_done,frame_ok,
 output wire cmd_valid,input wire cmd_ready,output wire cmd_write,
 output wire [27:0] cmd_addr,output wire [255:0] cmd_wdata,output wire [31:0] cmd_wstrb,
 input wire rsp_valid,rsp_write,mem_fault
);
 localparam IDLE=0,BLOCK=1,SEND=2,WAIT_RSP=3;
 reg [1:0] state;
 reg [27:0] address;
 reg [255:0] held_data;
 reg [31:0] held_strb;
 reg held_last,failed;
 wire accepted=cmd_valid&&cmd_ready;
 assign frame_start_ready=rst_n&&(state==IDLE)&&!mem_fault&&!frame_abort;
 assign block_ready=rst_n&&(state==BLOCK)&&!mem_fault&&!frame_abort;
 assign busy=(state!=IDLE);
 assign cmd_valid=rst_n&&(state==SEND);
 assign cmd_write=1'b1;
 assign cmd_addr=address;assign cmd_wdata=held_data;assign cmd_wstrb=held_strb;
 task retire;
  begin
   if(held_last||failed||frame_abort||mem_fault||!rsp_write||address==28'hffffff8)begin
    frame_done<=1;
    frame_ok<=held_last&&!failed&&!frame_abort&&!mem_fault&&rsp_write;
    state<=IDLE;
   end else begin address<=address+28'd8;state<=BLOCK;end
  end
 endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;address<=0;held_data<=0;held_strb<=0;held_last<=0;failed<=0;
   frame_done<=0;frame_ok<=0;
  end else begin
   frame_done<=0;frame_ok<=0;
   if(busy&&(frame_abort||mem_fault))failed<=1;
   case(state)
    IDLE:if(frame_start&&frame_start_ready)begin
     failed<=0;
     if(frame_base_byte[4:0]!=0||frame_base_byte[31:30]!=0)begin
      frame_done<=1;frame_ok<=0;
     end else begin address<=frame_base_byte[29:2];state<=BLOCK;end
    end
    BLOCK:begin
     if(frame_abort||mem_fault)begin frame_done<=1;state<=IDLE;end
     else if(block_valid&&block_ready)begin
      held_data<=block_data;held_strb<=block_strb;held_last<=block_last;state<=SEND;
     end
    end
    SEND:begin
     // Acceptance wins over cancellation: this command now needs draining.
     if(accepted)begin
      if(rsp_valid)retire;else state<=WAIT_RSP;
     end else if(frame_abort||mem_fault)begin frame_done<=1;state<=IDLE;end
    end
    WAIT_RSP:if(rsp_valid)retire;
    default:begin state<=IDLE;frame_done<=1;failed<=1;end
   endcase
  end
 end
endmodule
`default_nettype wire
