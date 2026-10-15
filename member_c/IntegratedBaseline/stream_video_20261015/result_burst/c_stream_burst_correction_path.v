`timescale 1ns/1ps
`default_nettype none
// C correction datapath, excluding capture/session ownership and HDMI scanout.
// Caller owns source bank from start through done/abort. After soft abort,
// already queued source reads can still retire; their old-generation responses
// are discarded. Re-capture writes must use the shared engine, invalidating its
// address-tagged source block cache before any newly captured bank is processed.
// Only shared hard reset may reset this path and the native DDR engine.
module c_stream_burst_correction_path #(
 parameter SRC_W=1920,SRC_H=1080,OUT_W=768,OUT_H=1080,
 parameter ACTIVE_W=765,ACTIVE_X=1,FIXED_IDENTITY=0,
 parameter [27:0]RESULT_BASE0=28'h0200000,RESULT_BASE1=28'h0400000,
 parameter CACHE_LINES=64
)(
 input wire proc_clk,ui_clk,rst_n,start,abort,nearest,input_geometry_valid,
 input wire[95:0]input_corners,input wire[27:0]source_base,input wire frame_bank,
 output wire start_ready,busy,output reg done,error,output reg[3:0]failure_reason,
 output wire[31:0]completed_pixels,processor_cycles,
 output wire cmd_valid,input wire cmd_ready,output wire cmd_write,cmd_source_block,
 output wire cmd_result_block,output wire[2047:0]result_block_data,
 output wire[27:0]cmd_addr,output wire[255:0]cmd_wdata,output wire[31:0]cmd_wstrb,
 input wire rsp_valid,rsp_write,input wire[255:0]rsp_rdata,
 input wire[2047:0]rsp_source_block,input wire engine_fault
);
 wire p_busy,p_done,p_error,writer_drained,writer_fault,bridge_fault,cache_fault;
 wire[3:0]p_reason;
 reg active,done_pending;reg[27:0]held_base;
 (* ASYNC_REG="TRUE" *) reg[2:0]ui_fault_sync;
 always @(posedge proc_clk or negedge rst_n)begin
  if(!rst_n)ui_fault_sync<=0;
  else ui_fault_sync<={ui_fault_sync[1:0],cache_fault||engine_fault};
 end
 wire hard_fault=ui_fault_sync[2]||writer_fault||bridge_fault;
 assign start_ready=rst_n&&!abort&&!p_busy&&!active&&!done_pending&&writer_drained&&!hard_fault;
 wire launch=start&&start_ready;
 assign busy=active||p_busy||done_pending||!writer_drained;
 always @(posedge proc_clk or negedge rst_n)begin
  if(!rst_n)begin active<=0;done_pending<=0;done<=0;error<=0;failure_reason<=0;held_base<=0;end
  else begin
   done<=0;error<=0;
   if(launch)begin active<=1;held_base<=source_base;failure_reason<=0;end
   if(p_done)done_pending<=1;
   if(done_pending&&writer_drained)begin done<=1;done_pending<=0;active<=0;end
   if(abort||p_error||hard_fault)begin
    active<=0;done_pending<=0;done<=0;
    if(p_error||hard_fault)begin error<=1;failure_reason<=ui_fault_sync[2]?4'd7:writer_fault?4'd6:bridge_fault?4'd11:p_reason;end
   end
  end
 end
 wire q_valid,q_ready,q_inside,q_nearest,r_valid,r_ready,r_inside;
 wire[23:0]q_addr00,q_addr10,q_addr01,q_addr11,q_tag,r_p00,r_p10,r_p01,r_p11,r_tag;
 wire[7:0]q_fx,q_fy,r_fx,r_fy;wire[31:0]q_generation,r_generation;
 wire write_valid,write_ready;wire[23:0]write_addr,write_rgb;
 frame_processor_stream #(.SRC_W(SRC_W),.SRC_H(SRC_H),.OUT_W(OUT_W),.OUT_H(OUT_H),.ACTIVE_W(ACTIVE_W),.ACTIVE_X(ACTIVE_X),.FIXED_IDENTITY(FIXED_IDENTITY)) processor(
 .clk(proc_clk),.rst_n(rst_n),.start(launch),.abort(abort||hard_fault),.nearest(nearest),.input_geometry_valid(input_geometry_valid),.input_corners(input_corners),
 .busy(p_busy),.done(p_done),.error(p_error),.failure_reason(p_reason),.cycles(processor_cycles),.completed_pixels(completed_pixels),.geometry_valid(),
 .q_valid(q_valid),.q_ready(q_ready),.q_inside(q_inside),.q_nearest(q_nearest),.q_addr00(q_addr00),.q_addr10(q_addr10),.q_addr01(q_addr01),.q_addr11(q_addr11),.q_tag(q_tag),.q_fx(q_fx),.q_fy(q_fy),.q_generation(q_generation),
 .r_valid(r_valid),.r_ready(r_ready),.r_inside(r_inside),.r_p00(r_p00),.r_p10(r_p10),.r_p01(r_p01),.r_p11(r_p11),.r_tag(r_tag),.r_fx(r_fx),.r_fy(r_fy),.r_generation(r_generation),
 .write_valid(write_valid),.write_ready(write_ready),.write_addr(write_addr),.write_rgb(write_rgb));
 wire req_valid,req_ready,req_nearest,req_inside,cache_rsp_valid,cache_rsp_ready,cache_rsp_inside;
 wire[27:0]req_base;wire[31:0]req_generation,cache_rsp_generation;wire[11:0]req_x,req_y;
 wire[23:0]req_tag,cache_p00,cache_p10,cache_p01,cache_p11,cache_tag;
 wire[7:0]req_fx,req_fy,cache_fx,cache_fy;
 quad_packet_bridge #(.SRC_W(SRC_W),.SRC_H(SRC_H),.OUT_W(OUT_W),.OUT_H(OUT_H)) bridge(
 .proc_clk(proc_clk),.ui_clk(ui_clk),.rst_n(rst_n),.q_base(held_base),.fault(bridge_fault),
 .q_valid(q_valid),.q_ready(q_ready),.q_inside(q_inside),.q_nearest(q_nearest),.q_addr00(q_addr00),.q_addr10(q_addr10),.q_addr01(q_addr01),.q_addr11(q_addr11),.q_tag(q_tag),.q_fx(q_fx),.q_fy(q_fy),.q_generation(q_generation),
 .req_valid(req_valid),.req_ready(req_ready),.req_base(req_base),.req_generation(req_generation),.req_x(req_x),.req_y(req_y),.req_nearest(req_nearest),.req_inside(req_inside),.req_tag(req_tag),.req_fx(req_fx),.req_fy(req_fy),
 .rsp_valid(cache_rsp_valid),.rsp_ready(cache_rsp_ready),.rsp_inside(cache_rsp_inside),.rsp_p00(cache_p00),.rsp_p10(cache_p10),.rsp_p01(cache_p01),.rsp_p11(cache_p11),.rsp_tag(cache_tag),.rsp_fx(cache_fx),.rsp_fy(cache_fy),.rsp_generation(cache_rsp_generation),
 .r_valid(r_valid),.r_ready(r_ready),.r_inside(r_inside),.r_p00(r_p00),.r_p10(r_p10),.r_p01(r_p01),.r_p11(r_p11),.r_tag(r_tag),.r_fx(r_fx),.r_fy(r_fy),.r_generation(r_generation));
 wire g_valid,g_ready,g_rsp_valid,g_rsp_write,w_valid,w_ready,w_write,w_rsp_valid,w_rsp_write;
 wire w_blockflag;wire[2047:0]w_block_data;
 wire[27:0]g_addr,w_addr;wire[255:0]w_data;wire[31:0]w_strb;
 ddr_quad_tile_cache #(.SRC_W(SRC_W),.SRC_H(SRC_H),.LINES(CACHE_LINES)) cache(
 .clk(ui_clk),.rst_n(rst_n),.req_valid(req_valid),.req_ready(req_ready),.req_base(req_base),.req_generation(req_generation),.req_x(req_x),.req_y(req_y),.req_nearest(req_nearest),.req_inside(req_inside),.req_tag(req_tag),.req_fx(req_fx),.req_fy(req_fy),
 .rsp_valid(cache_rsp_valid),.rsp_ready(cache_rsp_ready),.rsp_inside(cache_rsp_inside),.rsp_p00(cache_p00),.rsp_p10(cache_p10),.rsp_p01(cache_p01),.rsp_p11(cache_p11),.rsp_tag(cache_tag),.rsp_fx(cache_fx),.rsp_fy(cache_fy),.rsp_generation(cache_rsp_generation),
 .cmd_valid(g_valid),.cmd_ready(g_ready),.cmd_block(),.cmd_addr(g_addr),.mem_rsp_valid(g_rsp_valid),.mem_rsp_write(g_rsp_write),.rsp_block(rsp_source_block),.fault(cache_fault));
 ddr_result_writer_burst64 #(.OUT_W(OUT_W),.OUT_H(OUT_H),.BASE0(RESULT_BASE0),.BASE1(RESULT_BASE1)) writer(
 .clk(proc_clk),.rst_n(rst_n),.ui_clk(ui_clk),.ui_rst_n(rst_n),.frame_start(launch),.abort_frame(abort||p_error||hard_fault),.frame_bank(frame_bank),
 .write_valid(write_valid),.write_ready(write_ready),.write_addr(write_addr),.write_rgb(write_rgb),.drained(writer_drained),.fault(writer_fault),
 .cmd_valid(w_valid),.cmd_ready(w_ready),.cmd_write(w_write),.cmd_write_block(w_blockflag),.cmd_block_data(w_block_data),.cmd_addr(w_addr),.cmd_wdata(w_data),.cmd_wstrb(w_strb),.rsp_valid(w_rsp_valid),.rsp_write(w_rsp_write));
 // Result writes have priority, keeping the bounded output queue moving.
 // Full block data shares the DDR return bus; arbiter ownership qualifies valid.
 assign cmd_source_block=cmd_valid&&!w_valid;
 assign cmd_result_block=cmd_valid&&w_valid&&w_blockflag;assign result_block_data=w_block_data;
 ddr_arbiter3 arbiter(.clk(ui_clk),.rst_n(rst_n),.enabled(1'b1),
 .c0_valid(g_valid),.c0_write(1'b0),.c0_addr(g_addr),.c0_wdata(256'd0),.c0_wstrb(32'd0),.c0_ready(g_ready),.c0_rsp_valid(g_rsp_valid),.c0_rsp_write(g_rsp_write),.c0_rdata(),
 .c1_valid(w_valid),.c1_write(w_write),.c1_addr(w_addr),.c1_wdata(w_data),.c1_wstrb(w_strb),.c1_ready(w_ready),.c1_rsp_valid(w_rsp_valid),.c1_rsp_write(w_rsp_write),.c1_rdata(),
 .c2_valid(1'b0),.c2_write(1'b0),.c2_addr(28'd0),.c2_wdata(256'd0),.c2_wstrb(32'd0),.c2_ready(),.c2_rsp_valid(),.c2_rsp_write(),.c2_rdata(),
 .cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_write(cmd_write),.cmd_addr(cmd_addr),.cmd_wdata(cmd_wdata),.cmd_wstrb(cmd_wstrb),.rsp_valid(rsp_valid),.rsp_write(rsp_write),.rsp_rdata(rsp_rdata));
endmodule
`default_nettype wire


