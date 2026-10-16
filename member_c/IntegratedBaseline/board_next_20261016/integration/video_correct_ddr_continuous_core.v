`timescale 1ns/1ps
`default_nettype none
// System boundary for a DDR-backed source and two DDR result frames.
// The external UI engine serializes native 64-pixel result/source blocks.
// All domain reset inputs MUST share asynchronous hard assertion with that engine;
// local synchronizers may release on different cycles. Soft abort never resets ownership.
module video_correct_ddr_continuous_core #(
 parameter PROC_CYCLES_PER_MS=54000,MARKER_MODE=1,
 parameter IN_W=1920,IN_H=1080,SRC_W=1920,SRC_H=1080,OUT_W=768,OUT_H=1080,SCALE=1,
 parameter H_SYNC=44,H_BACK=148,H_ACTIVE=1920,H_FRONT=88,
 parameter V_SYNC=5,V_BACK=36,V_ACTIVE=1080,V_FRONT=4,
 parameter CAPTURE_TIMEOUT=54000000,RETRY_CYCLES=270000,
 parameter CAPTURE_BURST_BEATS=8,
 parameter FIFO_ADDR_BITS=9,BIST_BEATS=256,OVERLAP_CAPTURE=0,LATE_CAPTURE_PERCENT=0,ADAPTIVE_DISPLAY_GUARD=0,INLINE_GEOMETRY=0,
 parameter BLACK_RMIN=0,BLACK_RMAX=64,BLACK_GMIN=0,BLACK_GMAX=64,BLACK_BMIN=0,BLACK_BMAX=64,P0_XMIN=0,P0_XMAX=SRC_W/2-1,P0_YMIN=0,P0_YMAX=SRC_H/2-1,P1_XMIN=SRC_W/2,P1_XMAX=SRC_W-1,P1_YMIN=0,P1_YMAX=SRC_H/2-1,P2_XMIN=SRC_W/2,P2_XMAX=SRC_W-1,P2_YMIN=SRC_H/2,P2_YMAX=SRC_H-1,P3_XMIN=0,P3_XMAX=SRC_W/2-1,P3_YMIN=SRC_H/2,P3_YMAX=SRC_H-1,
 parameter [27:0] SOURCE_BASE1=28'h0800000,
 parameter MARKER_MIN_PIXELS=16,MARKER_MAX_PIXELS=4096,MARKER_MAX_SPAN=128,
 parameter [27:0] RESULT_BASE0=28'h0200000,RESULT_BASE1=28'h0400000,BIST_BASE=28'h0600000
)(
 input wire proc_clk,proc_rst_n,rx_clk,rx_rst_n,pix_clk,pix_rst_n,ui_clk,ui_rst_n,
 input wire hdmi_ready,ddr_ready,memory_fault,
 input wire rx_vs,rx_de,input wire [23:0] rx_rgb,
 input wire nearest,force_pattern,raw_requested,
 output reg[359:0]debug_h,output reg[95:0]debug_corners,output reg[31:0]debug_frame_id,output reg[27:0]debug_source_base,debug_result_base,output wire[31:0]debug_display_id,output wire debug_display_bank,output wire[FIFO_ADDR_BITS:0]data_fifo_peak,output wire display_raw,output wire[3:0]source_fault_components,
 output wire[31:0]raw_publications,corrected_publications,
 output wire hsync,vsync,de,output wire [23:0] rgb,
 output wire image_valid,working,frame_error,input_wait,display_underrun,
 output wire selftest_passed,selftest_failed,
 output wire [31:0] good_frames,rejected_frames,
 output wire[3:0]diagnostic_reason,output wire[3:0]diagnostic_phase,
 input wire preview_valid,overlay_on,input wire[23:0]preview_rgb,overlay_rgb,
 output wire[11:0]scan_x,scan_y,output wire scan_de,scan_start,scan_reset_n,
 output wire cmd_source_block,cmd_result_block,output wire[2047:0]result_block_data,input wire[2047:0]rsp_source_block,
 output wire[31:0]capture_frame_id,processing_frame_id,published_frame_id,displayed_frame_id,display_age_ms,admitted_frames,dropped_frames,output wire[511:0]rejected_reason_counts,
 output wire[2047:0]cmd_burst_data,output wire cmd_valid,cmd_write,output wire [27:0] cmd_addr,
 output wire [255:0] cmd_wdata,output wire [31:0] cmd_wstrb,
 input wire cmd_ready,rsp_valid,rsp_write,input wire [255:0] rsp_rdata
);
 wire test_v,test_r,test_write,test_rsp;
 wire [27:0] test_a;wire [255:0] test_data;wire [31:0] test_mask;
 ddr_self_test #(.BEATS(BIST_BEATS),.BASE(BIST_BASE)) selftest(.clk(ui_clk),.rst_n(ui_rst_n),
  .enabled(ddr_ready&&!memory_fault),.passed(selftest_passed),.failed(selftest_failed),
  .cmd_valid(test_v),.cmd_ready(test_r),.cmd_write(test_write),.cmd_addr(test_a),
  .cmd_wdata(test_data),.cmd_wstrb(test_mask),.rsp_valid(test_rsp),.rsp_write(rsp_write),.rsp_rdata(rsp_rdata));
 wire app_ready=selftest_passed&&!selftest_failed&&!memory_fault;
 (* ASYNC_REG="TRUE" *) reg [2:0] ready_sync,fault_sync;
 always @(posedge proc_clk or negedge proc_rst_n)begin
  if(!proc_rst_n)begin ready_sync<=0;fault_sync<=0;end
  else begin ready_sync<={ready_sync[1:0],app_ready};fault_sync<={fault_sync[1:0],memory_fault||selftest_failed};end
 end


 localparam SOURCE_WORDS=SRC_W*SRC_H,RESULT_WORDS=OUT_W*OUT_H;
 function interval_overlap;
  input[31:0]a,an,b,bn;
  begin interval_overlap=(a<b+bn)&&(b<a+an);end
 endfunction
 generate if(interval_overlap(0,SOURCE_WORDS,SOURCE_BASE1,SOURCE_WORDS)||
 interval_overlap(0,SOURCE_WORDS,RESULT_BASE0,RESULT_WORDS)||interval_overlap(0,SOURCE_WORDS,RESULT_BASE1,RESULT_WORDS)||
 interval_overlap(SOURCE_BASE1,SOURCE_WORDS,RESULT_BASE0,RESULT_WORDS)||interval_overlap(SOURCE_BASE1,SOURCE_WORDS,RESULT_BASE1,RESULT_WORDS)||
 interval_overlap(RESULT_BASE0,RESULT_WORDS,RESULT_BASE1,RESULT_WORDS)||
 interval_overlap(BIST_BASE,BIST_BEATS*8,0,SOURCE_WORDS)||interval_overlap(BIST_BASE,BIST_BEATS*8,SOURCE_BASE1,SOURCE_WORDS)||
 interval_overlap(BIST_BASE,BIST_BEATS*8,RESULT_BASE0,RESULT_WORDS)||interval_overlap(BIST_BASE,BIST_BEATS*8,RESULT_BASE1,RESULT_WORDS))begin: invalid_bank_layout
  C_SOURCE_RESULT_AND_BIST_BANKS_MUST_BE_DISJOINT parameter_error();
 end endgenerate
 wire common_rst_n=proc_rst_n&&ui_rst_n&&rx_rst_n;
 wire enabled=hdmi_ready&&ready_sync[2];
 wire frame_valid,frame_ready,descriptor_bank,geometry_valid,source_fault;
 wire[31:0]descriptor_generation,descriptor_capture_ms,source_rejected;
 wire[95:0]descriptor_corners;
 wire[511:0]source_reason_counts;
 wire[3:0]source_reason;
 wire release_valid,release_bank;wire[31:0]release_generation;
 wire cap_v,cap_r,cap_w,cap_rsp,cap_rsp_write;
 wire[27:0]cap_a;wire[255:0]cap_data;wire[31:0]cap_mask;
 continuous_source_path #(.MARKER_MODE(MARKER_MODE),.SRC_W(SRC_W),.SRC_H(SRC_H),.IN_W(IN_W),.IN_H(IN_H),
 .MIN_PIXELS(MARKER_MIN_PIXELS),.MAX_PIXELS(MARKER_MAX_PIXELS),.MAX_SPAN(MARKER_MAX_SPAN),.DATA_FIFO_ADDR_BITS(FIFO_ADDR_BITS),.BURST_BEATS(CAPTURE_BURST_BEATS),.PROC_CYCLES_PER_MS(PROC_CYCLES_PER_MS),.SOURCE_BASE0(28'd0),.SOURCE_BASE1(SOURCE_BASE1),
 .BLACK_RMIN(BLACK_RMIN),.BLACK_RMAX(BLACK_RMAX),.BLACK_GMIN(BLACK_GMIN),.BLACK_GMAX(BLACK_GMAX),.BLACK_BMIN(BLACK_BMIN),.BLACK_BMAX(BLACK_BMAX),.P0_XMIN(P0_XMIN),.P0_XMAX(P0_XMAX),.P0_YMIN(P0_YMIN),.P0_YMAX(P0_YMAX),.P1_XMIN(P1_XMIN),.P1_XMAX(P1_XMAX),.P1_YMIN(P1_YMIN),.P1_YMAX(P1_YMAX),.P2_XMIN(P2_XMIN),.P2_XMAX(P2_XMAX),.P2_YMIN(P2_YMIN),.P2_YMAX(P2_YMAX),.P3_XMIN(P3_XMIN),.P3_XMAX(P3_XMAX),.P3_YMIN(P3_YMIN),.P3_YMAX(P3_YMAX)) continuous_sources(
 .rx_clk(rx_clk),.proc_clk(proc_clk),.ui_clk(ui_clk),.rst_n(common_rst_n),.enabled(enabled),.raw_requested(raw_requested),.rx_vs(rx_vs),.rx_de(rx_de),.rx_rgb(rx_rgb),
 .frame_valid(frame_valid),.frame_ready(frame_ready),.frame_bank(descriptor_bank),.frame_generation(descriptor_generation),.frame_corners(descriptor_corners),.frame_geometry_valid(geometry_valid),.data_fifo_peak(data_fifo_peak),.frame_capture_ms(descriptor_capture_ms),
 .release_valid(release_valid),.release_bank(release_bank),.release_generation(release_generation),
 .rejected_frames(source_rejected),.dropped_frames(dropped_frames),.admitted_frames(admitted_frames),.reject_reason_counts(source_reason_counts),.last_failure_reason(source_reason),.fault(source_fault),.fault_components(source_fault_components),
 .cmd_valid(cap_v),.cmd_ready(cap_r),.cmd_write(cap_w),.cmd_addr(cap_a),.cmd_wdata(cap_data),.cmd_wstrb(cap_mask),.cmd_burst_data(cmd_burst_data),.rsp_valid(cap_rsp),.rsp_write(cap_rsp_write));
 assign capture_frame_id=admitted_frames;

 localparam WAIT_SOURCE=0,PROCESS=1,WAIT_DISPLAY=2;
 wire[2:0]state;wire write_bank,pub_toggle,pub_bank,pub_raw;
 wire source_bank,session_error;
 wire[31:0]published_generation,published_capture_ms,displayed_generation,displayed_capture_ms,processed_rejected;
 reg[511:0]processor_reason_counts;
 wire display_ack,p_done,p_error,p_busy,path_ready;
 wire[3:0]processor_reason,mode_reason;
 wire[31:0]p_pixels;wire[359:0]path_debug_h;reg[95:0]held_debug_corners;
 assign published_frame_id=published_generation;
 assign displayed_frame_id=displayed_generation;
 assign rejected_frames=source_rejected+processed_rejected;
 genvar reason_index;
 generate for(reason_index=0;reason_index<16;reason_index=reason_index+1)begin: reason_totals
 assign rejected_reason_counts[reason_index*32+:32]=source_reason_counts[reason_index*32+:32]+processor_reason_counts[reason_index*32+:32];
 end endgenerate
 (* ASYNC_REG="TRUE" *)reg[2:0]display_ack_sync,image_valid_sync;
 always @(posedge proc_clk or negedge common_rst_n)begin
  if(!common_rst_n)begin display_ack_sync<=0;image_valid_sync<=0;end
  else begin display_ack_sync<={display_ack_sync[1:0],display_ack};image_valid_sync<={image_valid_sync[1:0],image_valid};end
 end
 reg[31:0]clock_sub_ms,time_ms,no_source_timer,seen_admitted,seen_dropped,seen_rejected;
 always @(posedge proc_clk or negedge common_rst_n)begin
  if(!common_rst_n)begin clock_sub_ms<=0;time_ms<=0;no_source_timer<=0;seen_admitted<=0;seen_dropped<=0;end
  else begin
   if(clock_sub_ms==PROC_CYCLES_PER_MS-1)begin clock_sub_ms<=0;time_ms<=time_ms+1'b1;end
   else clock_sub_ms<=clock_sub_ms+1'b1;
   seen_admitted<=admitted_frames;seen_dropped<=dropped_frames;
   if(!enabled||seen_admitted!=admitted_frames||seen_dropped!=dropped_frames)no_source_timer<=0;
   else if(no_source_timer<CAPTURE_TIMEOUT-1)no_source_timer<=no_source_timer+1'b1;
  end
 end
 assign display_age_ms=image_valid_sync[2]?time_ms-displayed_capture_ms:32'd0;
 assign input_wait=enabled&&((no_source_timer==CAPTURE_TIMEOUT-1)||(!image_valid_sync[2]&&!frame_valid&&state==WAIT_SOURCE));
 assign working=p_busy||state==PROCESS;
 assign frame_error=session_error||fault_sync[2]||source_fault;
 assign diagnostic_phase=state==PROCESS?4'd5:state==WAIT_DISPLAY?4'd7:4'd0;
 wire start,abort_path;
 assign good_frames=raw_publications+corrected_publications;
 assign diagnostic_reason=(source_fault||fault_sync[2])?4'd7:input_wait?4'd1:mode_reason;
 reg[31:0]processing_generation,previous_rejected;
 assign processing_frame_id=processing_generation;
 always @(posedge proc_clk or negedge common_rst_n)begin
 if(!common_rst_n)begin processing_generation<=0;previous_rejected<=0;processor_reason_counts<=0;end
 else begin
 if(start)processing_generation<=descriptor_generation;
 previous_rejected<=processed_rejected;
 if(processed_rejected!=previous_rejected)
 processor_reason_counts[mode_reason*32+:32]<=processor_reason_counts[mode_reason*32+:32]+1'b1;
 end end
 c_frame_mode_controller modes(
 .clk(proc_clk),.rst_n(common_rst_n),.enabled(enabled),.raw_request(raw_requested),
 .frame_valid(frame_valid),.frame_bank(descriptor_bank),.frame_geometry_valid(geometry_valid),
 .frame_generation(descriptor_generation),.frame_capture_ms(descriptor_capture_ms),
 .frame_ready(frame_ready),.start_correct(start),.abort_correct(abort_path),
 .path_ready(path_ready),.path_busy(p_busy),.path_done(p_done),.path_error(p_error),
 .fault_condition(source_fault||fault_sync[2]),.path_failure_reason(processor_reason),.display_ack(display_ack_sync[2]),
 .source_select_bank(source_bank),.result_write_bank(write_bank),.publish_toggle(pub_toggle),.publish_bank(pub_bank),.publish_raw(pub_raw),
 .published_generation(published_generation),.published_capture_ms(published_capture_ms),
 .displayed_generation(displayed_generation),.displayed_capture_ms(displayed_capture_ms),
 .release_valid(release_valid),.release_bank(release_bank),.release_generation(release_generation),
 .raw_publications(raw_publications),.corrected_publications(corrected_publications),.rejected_frames(processed_rejected),
 .session_error(session_error),.reason(mode_reason),.state(state));
 wire br_v,br_r,br_w,br_rsp,br_rsp_write,br_source_block,br_result_block;
 wire[27:0]br_a;wire[255:0]br_data,br_rdata;wire[31:0]br_mask;
 c_stream_burst_correction_path #(.SRC_W(SRC_W),.SRC_H(SRC_H),.OUT_W(OUT_W),.OUT_H(OUT_H),.ACTIVE_W(OUT_W-3),.ACTIVE_X(1),.RESULT_BASE0(RESULT_BASE0),.RESULT_BASE1(RESULT_BASE1)) stream_path(
 .proc_clk(proc_clk),.ui_clk(ui_clk),.rst_n(common_rst_n),.start(start),.abort(abort_path),.nearest(nearest),.input_geometry_valid(geometry_valid),.input_corners(descriptor_corners),.source_base(source_bank?SOURCE_BASE1:28'd0),.frame_bank(write_bank),
 .start_ready(path_ready),.busy(p_busy),.done(p_done),.error(p_error),.failure_reason(processor_reason),.debug_h(path_debug_h),.completed_pixels(p_pixels),.processor_cycles(),
 .cmd_valid(br_v),.cmd_ready(br_r),.cmd_write(br_w),.cmd_source_block(br_source_block),.cmd_result_block(br_result_block),.result_block_data(result_block_data),.cmd_addr(br_a),.cmd_wdata(br_data),.cmd_wstrb(br_mask),
 .rsp_valid(br_rsp),.rsp_write(br_rsp_write),.rsp_rdata(br_rdata),.rsp_source_block(rsp_source_block),.engine_fault(memory_fault));
 wire display_v,display_r,display_rsp,display_prefetch_busy;wire [27:0] display_a;wire [255:0] display_rdata;
 wire display_source_block;
 ddr_result_display_raw_corrected #(.PUBLISH_LINE(V_SYNC),.SRC_W(SRC_W),.SRC_H(SRC_H),.SOURCE_BASE0(28'd0),.SOURCE_BASE1(SOURCE_BASE1),.OUT_W(OUT_W),.OUT_H(OUT_H),.SCALE(SCALE),.BASE0(RESULT_BASE0),.BASE1(RESULT_BASE1),
  .H_SYNC(H_SYNC),.H_BACK(H_BACK),.H_ACTIVE(H_ACTIVE),.H_FRONT(H_FRONT),
  .V_SYNC(V_SYNC),.V_BACK(V_BACK),.V_ACTIVE(V_ACTIVE),.V_FRONT(V_FRONT)) display_reader(
  .ui_clk(ui_clk),.ui_rst_n(ui_rst_n),.pix_clk(pix_clk),.pix_rst_n(pix_rst_n),
  .publish_toggle(pub_toggle),.publish_bank(pub_bank),.publish_raw(pub_raw),.publish_frame_id(published_generation),.display_frame_id(debug_display_id),.display_bank(debug_display_bank),.display_raw(display_raw),.scan_frame_pulse(),.image_swap_pulse(),.ack_toggle(display_ack),.preview_valid(preview_valid),.preview_rgb(preview_rgb),.overlay_on(overlay_on),.overlay_rgb(overlay_rgb),
  .scan_x(scan_x),.scan_y(scan_y),.scan_de(scan_de),.scan_start(scan_start),.scan_reset_n(scan_reset_n),
  .force_pattern(force_pattern),.capture_guard(1'b0),
  .cmd_valid(display_v),.cmd_source_block(display_source_block),.cmd_ready(display_r),.cmd_addr(display_a),.rsp_valid(display_rsp),.rsp_rdata(display_rdata),.rsp_block(rsp_source_block),
  .hsync(hsync),.vsync(vsync),.de(de),.rgb(rgb),.image_valid(image_valid),.underrun(display_underrun),.prefetch_busy(display_prefetch_busy));
 wire app_v,app_r,app_w,app_rsp;
 wire [27:0] app_a;wire [255:0] app_data;wire [31:0] app_mask;
 ddr_arbiter3_turnaround #(.BALANCE_C01(1)) ui_mux(.clk(ui_clk),.rst_n(ui_rst_n),.enabled(app_ready),
  .c0_valid(br_v),.c0_ready(br_r),.c0_write(br_w),.c0_addr(br_a),.c0_wdata(br_data),.c0_wstrb(br_mask),
  .c0_rsp_valid(br_rsp),.c0_rsp_write(br_rsp_write),.c0_rdata(br_rdata),
  .c1_valid(cap_v),.c1_ready(cap_r),.c1_write(cap_w),.c1_addr(cap_a),.c1_wdata(cap_data),.c1_wstrb(cap_mask),
  .c1_rsp_valid(cap_rsp),.c1_rsp_write(cap_rsp_write),.c1_rdata(),
  .c2_valid(display_v),.c2_ready(display_r),.c2_write(1'b0),.c2_addr(display_a),.c2_wdata(256'd0),.c2_wstrb(32'd0),
  .c2_rsp_valid(display_rsp),.c2_rsp_write(),.c2_rdata(display_rdata),
  .cmd_valid(app_v),.cmd_ready(app_r),.cmd_write(app_w),.cmd_addr(app_a),.cmd_wdata(app_data),.cmd_wstrb(app_mask),
  .rsp_valid(app_rsp),.rsp_write(rsp_write),.rsp_rdata(rsp_rdata));
 assign cmd_source_block=selftest_passed&&((br_r&&br_source_block)||(display_r&&display_source_block));
 assign cmd_result_block=selftest_passed&&br_r&&br_result_block;
 assign cmd_valid=ddr_ready&&!memory_fault&&(selftest_passed?app_v:test_v);
 assign cmd_write=selftest_passed?app_w:test_write;
 assign cmd_addr=selftest_passed?app_a:test_a;
 assign cmd_wdata=selftest_passed?app_data:test_data;
 assign cmd_wstrb=selftest_passed?app_mask:test_mask;
 assign test_r=!selftest_passed&&cmd_valid&&cmd_ready;
 assign app_r=selftest_passed&&cmd_valid&&cmd_ready;
 assign test_rsp=!selftest_passed&&rsp_valid;
 assign app_rsp=selftest_passed&&rsp_valid;
 always @(posedge proc_clk or negedge common_rst_n)begin
 if(!common_rst_n)begin debug_h<=0;debug_corners<=0;debug_frame_id<=0;debug_source_base<=0;debug_result_base<=0;held_debug_corners<=0;end
 else begin
 if(start)held_debug_corners<=descriptor_corners;
 if(p_done)begin debug_h<=path_debug_h;debug_corners<=held_debug_corners;debug_frame_id<=processing_generation;
 debug_source_base<=source_bank?SOURCE_BASE1:28'd0;debug_result_base<=write_bank?RESULT_BASE1:RESULT_BASE0;end
 end end
endmodule
`default_nettype wire
