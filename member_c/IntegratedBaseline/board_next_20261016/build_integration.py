"""Generate isolated application candidate from the exact frozen V4S inputs.

This does not produce a board project or authorize programming. Every inherited
input is hashed; B and the frozen release are read only.
"""
from pathlib import Path
import hashlib
import json

HERE = Path(__file__).resolve().parent
FROZEN = Path('D:/FPGA/output/c_stream_board_v4s_20261016')
OUT = HERE / 'integration'
OUT.mkdir(exist_ok=True)
inherited = {}

def load(relative):
    p = FROZEN / relative
    inherited[relative] = hashlib.sha256(p.read_bytes()).hexdigest()
    return p.read_text()

def replace(s, before, after):
    assert s.count(before) == 1, (before[:100], s.count(before))
    return s.replace(before, after)

s = load('rtl/stream/continuous_source_path.v')
s = replace(s, 'parameter SRC_W=1920', 'parameter MARKER_MODE=1,\n parameter SRC_W=1920')
s = replace(s, 'input wire rx_clk,proc_clk,ui_clk,rst_n,enabled,rx_vs,rx_de,', 'input wire rx_clk,proc_clk,ui_clk,rst_n,enabled,raw_requested,rx_vs,rx_de,')
s = replace(s, 'output wire fault,', 'output wire fault,output wire[3:0]fault_components,') if 'output wire fault,' in s else replace(s, 'output wire fault,\n', 'output wire fault,output wire[3:0]fault_components,\n')
s = replace(s, 'assign fault=rx_fault_sync', 'assign fault_components={geometry_fault,manager_fault,writer_fault_sync[2],rx_fault_sync[2]};\n assign fault=rx_fault_sync')
s = replace(s, 'continuous_capture_geometry #(', 'continuous_capture_geometry #(.MARKER_MODE(MARKER_MODE),')
s = replace(s, '.clk(proc_clk),.rst_n(rst_n),.allocation_valid', '.clk(proc_clk),.rst_n(rst_n),.raw_requested(raw_requested),.allocation_valid')
s = replace(s, 'output wire[31:0]frame_capture_ms,', 'output wire[DATA_FIFO_ADDR_BITS:0]data_fifo_peak,output wire[31:0]frame_capture_ms,')
s = replace(s, 'async_packet_stream #(.DATA_WIDTH(320)', 'async_packet_stream_monitored #(.DATA_WIDTH(320)')
s = replace(s, '.s_valid(packet_valid&&(!is_begin||alloc_source_ready)),', '.wr_peak(rx_fifo_peak),.s_valid(packet_valid&&(!is_begin||alloc_source_ready)),')
s = replace(s, 'wire queue_ready,alloc_source_ready;', '''wire queue_ready,alloc_source_ready;wire[DATA_FIFO_ADDR_BITS:0]rx_fifo_peak;
 snapshot_cdc #(.WIDTH(DATA_FIFO_ADDR_BITS+1)) fifo_peak_crossing(.s_clk(rx_clk),.d_clk(proc_clk),.rst_n(rst_n),.s_data(rx_fifo_peak),.d_data(data_fifo_peak),.d_valid());''')
(OUT / 'continuous_source_path.v').write_text(s)

# C-only observation ports; the original B vendor files remain untouched.
a=load('rtl/algo/c_corner_rectifier.v')
a=replace(a,'input wire clk,rst_n,','output wire[359:0]debug_h,input wire clk,rst_n,')
a=replace(a,'assign selected[j]=','assign debug_h[j*40+:40]=active[j];\n  assign selected[j]=')
(OUT/'c_corner_rectifier.v').write_text(a)
a=load('rtl/stream/frame_processor_stream.v')
a=replace(a,'input wire clk,rst_n,start,abort,nearest,input_geometry_valid,','output reg[359:0]debug_h,input wire clk,rst_n,start,abort,nearest,input_geometry_valid,')
a=replace(a,'localparam IDLE=0,','wire[359:0]math_debug_h;\n localparam IDLE=0,')
a=replace(a,'assign pending=1\'b1;', 'assign math_debug_h={40\'d16777216,120\'d0,40\'d16777216,120\'d0,40\'d16777216};assign pending=1\'b1;')
a=replace(a,'.clk(clk),.rst_n(math_reset_n),.src_valid', '.debug_h(math_debug_h),.clk(clk),.rst_n(math_reset_n),.src_valid')
a=replace(a,'endmodule','''// Preserve H across the math-only reset at processor completion. The first
 // RUN cycle follows the atomic coefficient commit and precedes all results.
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)debug_h<=0;else if(state==RUN&&issued==0)debug_h<=math_debug_h;
 end
endmodule''')
(OUT/'frame_processor_stream.v').write_text(a)
a=load('rtl/stream/c_stream_burst_correction_path.v')
a=replace(a,'output wire[31:0]completed_pixels,processor_cycles,','output wire[359:0]debug_h,output wire[31:0]completed_pixels,processor_cycles,')
a=replace(a,'.clk(proc_clk),.rst_n(rst_n),.start(launch)', '.debug_h(debug_h),.clk(proc_clk),.rst_n(rst_n),.start(launch)')
(OUT/'c_stream_burst_correction_path.v').write_text(a)
a=load('rtl/memory/async_packet_fifo.v')
a=replace(a,'output reg rd_valid,output wire empty','output reg rd_valid,output wire empty,output reg[ADDR_BITS:0]wr_peak')
a=replace(a,'endmodule','''// Conservative occupancy uses the existing synchronized read pointer.
 reg[PTR_BITS-1:0]level_q;wire[PTR_BITS-1:0]read_binary;
 genvar pn;generate for(pn=0;pn<PTR_BITS;pn=pn+1)begin: peak_decode
 assign read_binary[pn]=^(rd_gray_w2>>pn);end endgenerate
 always @(posedge wr_clk or negedge wr_local_rst_n)begin
 if(!wr_local_rst_n)begin level_q<=0;wr_peak<=0;end
 else begin level_q<=wr_bin-read_binary;if(level_q>wr_peak)wr_peak<=level_q;end end
endmodule''')
a=replace(a,'module async_packet_fifo #(', 'module async_packet_fifo_monitored #(')
(OUT/'async_packet_fifo_monitored.v').write_text(a)
a=load('rtl/stream/async_packet_stream.v')
a=replace(a,'input wire wr_clk,rd_clk,rst_n,','output wire[ADDR_BITS:0]wr_peak,input wire wr_clk,rd_clk,rst_n,')
a=replace(a,'.wr_en(s_valid&&s_ready),', '.wr_peak(wr_peak),.wr_en(s_valid&&s_ready),')
a=replace(a,'module async_packet_stream #(', 'module async_packet_stream_monitored #(')
a=replace(a,'async_packet_fifo #(', 'async_packet_fifo_monitored #(')
(OUT/'async_packet_stream_monitored.v').write_text(a)

s = load('rtl/top/video_correct_ddr_continuous_core.v')
s = replace(s, 'parameter PROC_CYCLES_PER_MS=54000,', 'parameter PROC_CYCLES_PER_MS=54000,MARKER_MODE=1,')
s = replace(s, 'input wire nearest,force_pattern,', 'input wire nearest,force_pattern,raw_requested,\n output wire display_raw,output wire[3:0]source_fault_components,\n output wire[31:0]raw_publications,corrected_publications,')
s = replace(s, 'output wire display_raw,', 'output reg[359:0]debug_h,output reg[95:0]debug_corners,output reg[31:0]debug_frame_id,output reg[27:0]debug_source_base,debug_result_base,output wire[31:0]debug_display_id,output wire debug_display_bank,output wire[FIFO_ADDR_BITS:0]data_fifo_peak,output wire display_raw,')
s = replace(s, '.frame_capture_ms(descriptor_capture_ms),', '.data_fifo_peak(data_fifo_peak),.frame_capture_ms(descriptor_capture_ms),')
s = replace(s, 'assign capture_frame_id=admitted_frames;', '''assign capture_frame_id=admitted_frames;
 always @(posedge proc_clk or negedge common_rst_n)begin
 if(!common_rst_n)begin debug_h<=0;debug_corners<=0;debug_frame_id<=0;debug_source_base<=0;debug_result_base<=0;held_debug_corners<=0;end
 else begin
 if(start)held_debug_corners<=descriptor_corners;
 if(p_done)begin debug_h<=path_debug_h;debug_corners<=held_debug_corners;debug_frame_id<=processing_generation;
 debug_source_base<=source_bank?SOURCE_BASE1:28'd0;debug_result_base<=write_bank?RESULT_BASE1:RESULT_BASE0;end
 end end''')
s = replace(s, 'output reg[3:0]diagnostic_reason', 'output wire[3:0]diagnostic_reason')
s = replace(s, 'reg release_valid,release_bank;reg[31:0]release_generation;', 'wire release_valid,release_bank;wire[31:0]release_generation;')
s = replace(s, 'continuous_source_path #(', 'continuous_source_path #(.MARKER_MODE(MARKER_MODE),')
s = replace(s, '.rst_n(common_rst_n),.enabled(enabled),.rx_vs', '.rst_n(common_rst_n),.enabled(enabled),.raw_requested(raw_requested),.rx_vs')
s = replace(s, '.fault(source_fault),', '.fault(source_fault),.fault_components(source_fault_components),')
start = s.index(' localparam WAIT_SOURCE=0,PROCESS=1,WAIT_DISPLAY=2;')
end = s.index(' (* ASYNC_REG="TRUE" *)reg[2:0]display_ack_sync', start)
s = s[:start] + ''' localparam WAIT_SOURCE=0,PROCESS=1,WAIT_DISPLAY=2;
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
''' + s[end:]
start = s.index(' assign frame_ready=common_rst_n')
end = s.index(' wire br_v,br_r,br_w', start)
s = s[:start] + ''' wire start,abort_path;
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
''' + s[end:]
s = replace(s, 'ddr_result_display_block64 #(', 'wire display_source_block;\n ddr_result_display_raw_corrected #(.PUBLISH_LINE(V_SYNC),.SRC_W(SRC_W),.SRC_H(SRC_H),.SOURCE_BASE0(28\'d0),.SOURCE_BASE1(SOURCE_BASE1),')
s = replace(s, '.publish_toggle(pub_toggle),.publish_bank(pub_bank),', '.publish_toggle(pub_toggle),.publish_bank(pub_bank),') if False else s
# This exact occurrence is the display instance (the controller uses output connections).
s = replace(s, '.publish_bank(pub_bank),.ack_toggle(display_ack)', '.publish_bank(pub_bank),.publish_raw(pub_raw),.publish_frame_id(published_generation),.display_frame_id(debug_display_id),.display_bank(debug_display_bank),.display_raw(display_raw),.scan_frame_pulse(),.image_swap_pulse(),.ack_toggle(display_ack)')
s = replace(s, '.cmd_valid(display_v),.cmd_ready', '.cmd_valid(display_v),.cmd_source_block(display_source_block),.cmd_ready')
s = replace(s, 'assign cmd_source_block=selftest_passed&&br_r&&br_source_block;', 'assign cmd_source_block=selftest_passed&&((br_r&&br_source_block)||(display_r&&display_source_block));')
s = replace(s, '.completed_pixels(p_pixels),', '.debug_h(path_debug_h),.completed_pixels(p_pixels),')
begin=s.index(' always @(posedge proc_clk or negedge common_rst_n)begin\n if(!common_rst_n)begin debug_h<=')
end=s.index(' end end',begin)+len(' end end')
debug_block=s[begin:end]
s=s[:begin]+s[end:]
s=replace(s,'endmodule',debug_block+'\nendmodule')
(OUT / 'video_correct_ddr_continuous_core.v').write_text(s)

old_sources = json.loads((HERE.parent / 'stream_video_20261015/continuous_system_test/sources.json').read_text())
overrides = {**{n:OUT/n for n in ['c_corner_rectifier.v','frame_processor_stream.v','c_stream_burst_correction_path.v']},
 'video_correct_ddr_continuous_core.v': OUT/'video_correct_ddr_continuous_core.v',
 'continuous_source_path.v': OUT/'continuous_source_path.v',
 'continuous_capture_manager.v': HERE/'control/manager_raw.v',
 'continuous_capture_geometry.v': HERE/'geometry/continuous_capture_geometry.v',
 'ddr_result_display_block64.v': HERE/'display/ddr_result_display_raw_corrected.v',
}
sources=[]
for source in old_sources:
    p=Path(source)
    if p.suffix == '.sv': continue
    if p.name == 'ddr_result_display.v': continue  # old wrapper is not instantiated
    sources.append(str(overrides.get(p.name,p)).replace('\\','/'))
sources.extend([(OUT/'async_packet_fifo_monitored.v').as_posix(),(OUT/'async_packet_stream_monitored.v').as_posix()])
for relative in ['diagnostics/snapshot_cdc.v','control/c_frame_mode_controller.v','geometry/color_marker_detector.v','geometry/marker_color_classifier.v','geometry/quad_geometry_guard.v']:
    sources.append((HERE/relative).as_posix())
(OUT/'sources.json').write_text(json.dumps(sources,indent=2)+'\n')
manifest = {'status':'application integration candidate; not board qualified',
            'frozen_inputs':inherited,
            'sources':{p:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in sources}}
(OUT/'source_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Generated isolated application candidate:',OUT)
