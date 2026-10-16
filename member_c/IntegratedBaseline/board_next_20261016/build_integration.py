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
(OUT / 'continuous_source_path.v').write_text(s)

s = load('rtl/top/video_correct_ddr_continuous_core.v')
s = replace(s, 'parameter PROC_CYCLES_PER_MS=54000,', 'parameter PROC_CYCLES_PER_MS=54000,MARKER_MODE=1,')
s = replace(s, 'input wire nearest,force_pattern,', 'input wire nearest,force_pattern,raw_requested,\n output wire display_raw,output wire[3:0]source_fault_components,\n output wire[31:0]raw_publications,corrected_publications,')
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
 wire[31:0]p_pixels;
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
s = replace(s, 'ddr_result_display_block64 #(', 'wire display_source_block;\n ddr_result_display_raw_corrected #(.SRC_W(SRC_W),.SRC_H(SRC_H),.SOURCE_BASE0(28\'d0),.SOURCE_BASE1(SOURCE_BASE1),')
s = replace(s, '.publish_toggle(pub_toggle),.publish_bank(pub_bank),', '.publish_toggle(pub_toggle),.publish_bank(pub_bank),') if False else s
# This exact occurrence is the display instance (the controller uses output connections).
s = replace(s, '.publish_bank(pub_bank),.ack_toggle(display_ack)', '.publish_bank(pub_bank),.publish_raw(pub_raw),.display_raw(display_raw),.scan_frame_pulse(),.image_swap_pulse(),.ack_toggle(display_ack)')
s = replace(s, '.cmd_valid(display_v),.cmd_ready', '.cmd_valid(display_v),.cmd_source_block(display_source_block),.cmd_ready')
s = replace(s, 'assign cmd_source_block=selftest_passed&&br_r&&br_source_block;', 'assign cmd_source_block=selftest_passed&&((br_r&&br_source_block)||(display_r&&display_source_block));')
(OUT / 'video_correct_ddr_continuous_core.v').write_text(s)

old_sources = json.loads((HERE.parent / 'stream_video_20261015/continuous_system_test/sources.json').read_text())
overrides = {
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
for relative in ['control/c_frame_mode_controller.v','geometry/color_marker_detector.v','geometry/marker_color_classifier.v','geometry/quad_geometry_guard.v']:
    sources.append((HERE/relative).as_posix())
(OUT/'sources.json').write_text(json.dumps(sources,indent=2)+'\n')
manifest = {'status':'application integration candidate; not board qualified',
            'frozen_inputs':inherited,
            'sources':{p:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in sources}}
(OUT/'source_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Generated isolated application candidate:',OUT)
