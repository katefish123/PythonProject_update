`timescale 1ns/1ps
`default_nettype none
// System boundary for a DDR-backed source and two DDR result frames.
// The external UI memory engine is single-transaction, 256 bits / command.
module video_correct_ddr_core #(
 parameter IN_W=1920,IN_H=1080,SRC_W=640,SRC_H=480,OUT_W=320,OUT_H=452,SCALE=2,
 parameter H_SYNC=44,H_BACK=148,H_ACTIVE=1920,H_FRONT=88,
 parameter V_SYNC=5,V_BACK=36,V_ACTIVE=1080,V_FRONT=4,
 parameter CAPTURE_TIMEOUT=54000000,RETRY_CYCLES=270000,
 parameter FIFO_ADDR_BITS=9,BIST_BEATS=256
)(
 input wire proc_clk,proc_rst_n,rx_clk,rx_rst_n,pix_clk,pix_rst_n,ui_clk,ui_rst_n,
 input wire hdmi_ready,ddr_ready,memory_fault,
 input wire rx_vs,rx_de,input wire [23:0] rx_rgb,
 input wire nearest,force_pattern,
 output wire hsync,vsync,de,output wire [23:0] rgb,
 output wire image_valid,working,frame_error,input_wait,display_underrun,
 output wire selftest_passed,selftest_failed,
 output wire [31:0] good_frames,rejected_frames,
 output wire cmd_valid,cmd_write,output wire [27:0] cmd_addr,
 output wire [255:0] cmd_wdata,output wire [31:0] cmd_wstrb,
 input wire cmd_ready,rsp_valid,rsp_write,input wire [255:0] rsp_rdata,
 output wire [95:0] diagnostic_rx,output wire [127:0] diagnostic_proc,
 output reg [191:0] diagnostic_marker,output wire [63:0] diagnostic_ui
);
 wire test_v,test_r,test_write,test_rsp;
 wire [27:0] test_a;wire [255:0] test_data;wire [31:0] test_mask;
 ddr_self_test #(.BEATS(BIST_BEATS)) selftest(.clk(ui_clk),.rst_n(ui_rst_n),
  .enabled(ddr_ready&&!memory_fault),.passed(selftest_passed),.failed(selftest_failed),
  .cmd_valid(test_v),.cmd_ready(test_r),.cmd_write(test_write),.cmd_addr(test_a),
  .cmd_wdata(test_data),.cmd_wstrb(test_mask),.rsp_valid(test_rsp),.rsp_write(rsp_write),.rsp_rdata(rsp_rdata));
 wire app_ready=selftest_passed&&!selftest_failed&&!memory_fault;
 (* ASYNC_REG="TRUE" *) reg [2:0] ready_sync,fault_sync;
 always @(posedge proc_clk or negedge proc_rst_n)begin
  if(!proc_rst_n)begin ready_sync<=0;fault_sync<=0;end
  else begin ready_sync<={ready_sync[1:0],app_ready};fault_sync<={fault_sync[1:0],memory_fault};end
 end
 wire capture_req,capture_ack,capture_good,start,processor_rst;
 wire p_done,p_error,p_busy,writer_drained,writer_fault;
 wire write_bank,pub_toggle,pub_bank,display_ack,session_error;
 reg done_pending,complete_pulse;
 wire all_error=p_error||writer_fault||fault_sync[2];
 wire [3:0] session_state,processor_state;
 wire [7:0] processor_error_code;
 wire [191:0] marker_snapshot;
 wire [31:0] processor_cycles;
 reg [7:0] last_failure;
 assign diagnostic_proc={8'd0,hdmi_ready,ready_sync[2],fault_sync[2],p_busy,p_done,p_error,session_error,writer_fault,
   good_frames,rejected_frames,last_failure,session_state,processor_state,processor_cycles};
 always @(posedge proc_clk or negedge proc_rst_n)begin
  if(!proc_rst_n)begin last_failure<=0;diagnostic_marker<=0;end
  else if(p_error||p_done)begin last_failure<=p_error?processor_error_code:8'd0;diagnostic_marker<=marker_snapshot;end
 end
 always @(posedge proc_clk or negedge proc_rst_n)begin
  if(!proc_rst_n)begin done_pending<=0;complete_pulse<=0;end
  else begin
   complete_pulse<=0;
   if(p_done)done_pending<=1;
   if(done_pending&&writer_drained&&!all_error)begin complete_pulse<=1;done_pending<=0;end
   if(start||all_error)done_pending<=0;
  end
 end
 assign frame_error=session_error||fault_sync[2];
 frame_session #(.CAPTURE_TIMEOUT(CAPTURE_TIMEOUT),.RETRY_CYCLES(RETRY_CYCLES)) session(
  .clk(proc_clk),.rst_n(proc_rst_n),.enabled(hdmi_ready&&ready_sync[2]),
  .capture_request(capture_req),.capture_complete(capture_ack),.capture_ok(capture_good),
  .processor_start(start),.processor_reset_n(processor_rst),.processor_done(complete_pulse),.processor_error(all_error),
  .write_bank(write_bank),.publish_toggle(pub_toggle),.publish_bank(pub_bank),.display_ack(display_ack),
  .diagnostic_state(session_state),.frame_error(session_error),.input_wait(input_wait),.working(working),.good_frames(good_frames),.rejected_frames(rejected_frames));

 wire fifo_full,fifo_empty,fifo_we,fifo_re,fifo_rvalid;
 wire [284:0] fifo_wdata,fifo_rdata;
 wire rx_complete,rx_good;
 ddr_snapshot_capture #(.IN_W(IN_W),.IN_H(IN_H),.SRC_W(SRC_W),.SRC_H(SRC_H)) source_capture(
  .rx_clk(rx_clk),.rx_rst_n(rx_rst_n),.rx_vs(rx_vs),.rx_de(rx_de),.rx_rgb(rx_rgb),.request_toggle(capture_req),
  .diagnostic_snapshot(diagnostic_rx),.fifo_full(fifo_full),.rx_complete_toggle(rx_complete),.capture_ok(rx_good),.fifo_wr_en(fifo_we),.fifo_wr_data(fifo_wdata));
 async_packet_fifo #(.DATA_WIDTH(285),.ADDR_BITS(FIFO_ADDR_BITS)) capture_fifo(
  .wr_clk(rx_clk),.rd_clk(ui_clk),.rst_n(rx_rst_n&&ui_rst_n),
  .wr_en(fifo_we),.wr_data(fifo_wdata),.full(fifo_full),.rd_en(fifo_re),.rd_data(fifo_rdata),.rd_valid(fifo_rvalid),.empty(fifo_empty));
 wire cap_v,cap_r,cap_w,cap_rsp,cap_rsp_write;
 wire [27:0] cap_a;wire [255:0] cap_data,cap_rdata;wire [31:0] cap_mask;
 ddr_capture_writer #(.SRC_W(SRC_W),.SRC_H(SRC_H)) capture_writer(
  .ui_clk(ui_clk),.ui_rst_n(ui_rst_n),.request_toggle(capture_req),.rx_complete_toggle(rx_complete),.rx_capture_ok(rx_good),
  .fifo_empty(fifo_empty),.fifo_rd_data(fifo_rdata),.fifo_rd_valid(fifo_rvalid),.fifo_rd_en(fifo_re),
  .cmd_valid(cap_v),.cmd_ready(cap_r),.cmd_write(cap_w),.cmd_addr(cap_a),.cmd_wdata(cap_data),.cmd_wstrb(cap_mask),
  .diagnostic_snapshot(),.rsp_valid(cap_rsp),.rsp_write(cap_rsp_write),.complete_toggle(capture_ack),.capture_ok(capture_good));

 wire mem_v,mem_ready,mem_rsp,wr_v,wr_ready;
 wire [23:0] mem_a,mem_rgb,wr_a,wr_rgb;
 frame_processor #(.SRC_W(SRC_W),.SRC_H(SRC_H),.OUT_W(OUT_W),.OUT_H(OUT_H)) processor(
  .clk(proc_clk),.rst_n(processor_rst),.start(start),.nearest(nearest),.busy(p_busy),.done(p_done),.error(p_error),
  .mem_valid(mem_v),.mem_ready(mem_ready),.mem_addr(mem_a),.mem_rsp_valid(mem_rsp),.mem_rgb(mem_rgb),
  .write_valid(wr_v),.write_ready(wr_ready),.write_addr(wr_a),.write_rgb(wr_rgb),
  .diagnostic_state(processor_state),.diagnostic_error(processor_error_code),.diagnostic_marker(marker_snapshot),
  .cycles(processor_cycles),.completed_pixels(),.geometry_valid());
 wire cache_v,cache_r,cache_w,cache_rsp,cache_rsp_write;
 wire [27:0] cache_a;wire [255:0] cache_data,cache_rdata;wire [31:0] cache_mask;
 ddr_pixel_cache source_cache(.clk(proc_clk),.rst_n(processor_rst),.invalidate(start),
  .mem_valid(mem_v),.mem_ready(mem_ready),.mem_addr(mem_a),.mem_rsp_valid(mem_rsp),.mem_rgb(mem_rgb),.base_word_addr(28'd0),
  .cmd_valid(cache_v),.cmd_ready(cache_r),.cmd_write(cache_w),.cmd_addr(cache_a),.cmd_wdata(cache_data),.cmd_wstrb(cache_mask),
  .rsp_valid(cache_rsp),.rsp_write(cache_rsp_write),.rsp_rdata(cache_rdata));
 wire dest_v,dest_r,dest_w,dest_rsp,dest_rsp_write;
 wire [27:0] dest_a;wire [255:0] dest_data,dest_rdata;wire [31:0] dest_mask;
 ddr_result_writer #(.OUT_W(OUT_W),.OUT_H(OUT_H)) destination_writer(
  .clk(proc_clk),.rst_n(proc_rst_n),.frame_start(start),.abort_frame(all_error),.frame_bank(write_bank),
  .write_valid(wr_v),.write_ready(wr_ready),.write_addr(wr_a),.write_rgb(wr_rgb),.drained(writer_drained),.fault(writer_fault),
  .cmd_valid(dest_v),.cmd_ready(dest_r),.cmd_write(dest_w),.cmd_addr(dest_a),.cmd_wdata(dest_data),.cmd_wstrb(dest_mask),
  .rsp_valid(dest_rsp),.rsp_write(dest_rsp_write));
 wire pc_v,pc_r,pc_w,pc_rsp,pc_rsp_write;
 wire [27:0] pc_a;wire [255:0] pc_data,pc_rdata;wire [31:0] pc_mask;
 ddr_arbiter3 processor_mux(.clk(proc_clk),.rst_n(proc_rst_n),.enabled(1'b1),
  .c0_valid(cache_v),.c0_ready(cache_r),.c0_write(cache_w),.c0_addr(cache_a),.c0_wdata(cache_data),.c0_wstrb(cache_mask),
  .c0_rsp_valid(cache_rsp),.c0_rsp_write(cache_rsp_write),.c0_rdata(cache_rdata),
  .c1_valid(dest_v),.c1_ready(dest_r),.c1_write(dest_w),.c1_addr(dest_a),.c1_wdata(dest_data),.c1_wstrb(dest_mask),
  .c1_rsp_valid(dest_rsp),.c1_rsp_write(dest_rsp_write),.c1_rdata(dest_rdata),
  .c2_valid(1'b0),.c2_write(1'b0),.c2_addr(28'd0),.c2_wdata(256'd0),.c2_wstrb(32'd0),.c2_ready(),.c2_rsp_valid(),.c2_rsp_write(),.c2_rdata(),
  .cmd_valid(pc_v),.cmd_ready(pc_r),.cmd_write(pc_w),.cmd_addr(pc_a),.cmd_wdata(pc_data),.cmd_wstrb(pc_mask),
  .rsp_valid(pc_rsp),.rsp_write(pc_rsp_write),.rsp_rdata(pc_rdata));
 wire br_v,br_r,br_w,br_rsp,br_rsp_write;
 wire [27:0] br_a;wire [255:0] br_data,br_rdata;wire [31:0] br_mask;
 ddr_command_bridge processor_bridge(.src_clk(proc_clk),.src_rst_n(proc_rst_n),.dst_clk(ui_clk),.dst_rst_n(ui_rst_n),
  .src_cmd_valid(pc_v),.src_cmd_ready(pc_r),.src_cmd_write(pc_w),.src_cmd_addr(pc_a),.src_cmd_wdata(pc_data),.src_cmd_wstrb(pc_mask),
  .src_rsp_valid(pc_rsp),.src_rsp_write(pc_rsp_write),.src_rsp_rdata(pc_rdata),
  .dst_cmd_valid(br_v),.dst_cmd_ready(br_r),.dst_cmd_write(br_w),.dst_cmd_addr(br_a),.dst_cmd_wdata(br_data),.dst_cmd_wstrb(br_mask),
  .dst_rsp_valid(br_rsp),.dst_rsp_write(br_rsp_write),.dst_rsp_rdata(br_rdata));
 wire display_v,display_r,display_rsp;wire [27:0] display_a;wire [255:0] display_rdata;
 ddr_result_display #(.OUT_W(OUT_W),.OUT_H(OUT_H),.SCALE(SCALE),
  .H_SYNC(H_SYNC),.H_BACK(H_BACK),.H_ACTIVE(H_ACTIVE),.H_FRONT(H_FRONT),
  .V_SYNC(V_SYNC),.V_BACK(V_BACK),.V_ACTIVE(V_ACTIVE),.V_FRONT(V_FRONT)) display_reader(
  .ui_clk(ui_clk),.ui_rst_n(ui_rst_n),.pix_clk(pix_clk),.pix_rst_n(pix_rst_n),
  .publish_toggle(pub_toggle),.publish_bank(pub_bank),.ack_toggle(display_ack),.force_pattern(force_pattern),
  .diagnostic_snapshot(diagnostic_ui),.cmd_valid(display_v),.cmd_ready(display_r),.cmd_addr(display_a),.rsp_valid(display_rsp),.rsp_rdata(display_rdata),
  .hsync(hsync),.vsync(vsync),.de(de),.rgb(rgb),.image_valid(image_valid),.underrun(display_underrun));
 wire app_v,app_r,app_w,app_rsp;
 wire [27:0] app_a;wire [255:0] app_data;wire [31:0] app_mask;
 ddr_arbiter3 ui_mux(.clk(ui_clk),.rst_n(ui_rst_n),.enabled(app_ready),
  .c0_valid(br_v),.c0_ready(br_r),.c0_write(br_w),.c0_addr(br_a),.c0_wdata(br_data),.c0_wstrb(br_mask),
  .c0_rsp_valid(br_rsp),.c0_rsp_write(br_rsp_write),.c0_rdata(br_rdata),
  .c1_valid(cap_v),.c1_ready(cap_r),.c1_write(cap_w),.c1_addr(cap_a),.c1_wdata(cap_data),.c1_wstrb(cap_mask),
  .c1_rsp_valid(cap_rsp),.c1_rsp_write(cap_rsp_write),.c1_rdata(cap_rdata),
  .c2_valid(display_v),.c2_ready(display_r),.c2_write(1'b0),.c2_addr(display_a),.c2_wdata(256'd0),.c2_wstrb(32'd0),
  .c2_rsp_valid(display_rsp),.c2_rsp_write(),.c2_rdata(display_rdata),
  .cmd_valid(app_v),.cmd_ready(app_r),.cmd_write(app_w),.cmd_addr(app_a),.cmd_wdata(app_data),.cmd_wstrb(app_mask),
  .rsp_valid(app_rsp),.rsp_write(rsp_write),.rsp_rdata(rsp_rdata));
 assign cmd_valid=ddr_ready&&!memory_fault&&(selftest_passed?app_v:test_v);
 assign cmd_write=selftest_passed?app_w:test_write;
 assign cmd_addr=selftest_passed?app_a:test_a;
 assign cmd_wdata=selftest_passed?app_data:test_data;
 assign cmd_wstrb=selftest_passed?app_mask:test_mask;
 assign test_r=!selftest_passed&&cmd_valid&&cmd_ready;
 assign app_r=selftest_passed&&cmd_valid&&cmd_ready;
 assign test_rsp=!selftest_passed&&rsp_valid;
 assign app_rsp=selftest_passed&&rsp_valid;
endmodule
`default_nettype wire
