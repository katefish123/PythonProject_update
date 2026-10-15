`timescale 1ns/1ps
`default_nettype none
// The base and request form a bundled CDC interface. Keep base_word_addr stable
// before request_toggle and through its three UI-clock synchronization stages.
// One base is latched per request; later base changes cannot move active writes.
// rsp_valid is passed unchanged: the DDR engine must assert one response only
// after the entire BURST_BEATS transaction has retired, never per physical beat.
module ddr_capture_writer_banked #(
 parameter SRC_W=640,SRC_H=480,EMPTY_QUIET_CYCLES=4,BURST_BEATS=1
)(
 input wire ui_clk,ui_rst_n,request_toggle,rx_complete_toggle,rx_capture_ok,
 input wire [3:0] rx_failure_reason,
 input wire [27:0] base_word_addr,
 output wire fifo_rd_en,input wire fifo_empty,input wire [284:0] fifo_rd_data,input wire fifo_rd_valid,
 output wire cmd_valid,input wire cmd_ready,
 output wire [2047:0] cmd_burst_data,
 output wire cmd_write,output wire [27:0] cmd_addr,output wire [255:0] cmd_wdata,output wire [31:0] cmd_wstrb,
 input wire rsp_valid,rsp_write,
 output wire complete_toggle,capture_ok,output wire [3:0] failure_reason
);
 (* ASYNC_REG="TRUE" *) reg [2:0] request_sync;
 reg token;
 reg [27:0] active_base;
 wire [27:0] relative_addr;
 assign cmd_addr=active_base+relative_addr;
 always @(posedge ui_clk or negedge ui_rst_n)begin
  if(!ui_rst_n)begin request_sync<=0;token<=0;active_base<=0;end
  else begin
   request_sync<={request_sync[1:0],request_toggle};
   if(request_sync[2]!=token)begin token<=request_sync[2];active_base<=base_word_addr;end
  end
 end
 ddr_capture_writer #(.SRC_W(SRC_W),.SRC_H(SRC_H),.EMPTY_QUIET_CYCLES(EMPTY_QUIET_CYCLES),.BURST_BEATS(BURST_BEATS)) writer(
  .ui_clk(ui_clk),.ui_rst_n(ui_rst_n),.request_toggle(request_toggle),
  .rx_complete_toggle(rx_complete_toggle),.rx_capture_ok(rx_capture_ok),.rx_failure_reason(rx_failure_reason),
  .fifo_rd_en(fifo_rd_en),.fifo_empty(fifo_empty),.fifo_rd_data(fifo_rd_data),.fifo_rd_valid(fifo_rd_valid),
  .cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_burst_data(cmd_burst_data),.cmd_write(cmd_write),.cmd_addr(relative_addr),.cmd_wdata(cmd_wdata),.cmd_wstrb(cmd_wstrb),
  .rsp_valid(rsp_valid),.rsp_write(rsp_write),.complete_toggle(complete_toggle),.capture_ok(capture_ok),.failure_reason(failure_reason));
endmodule
`default_nettype wire
