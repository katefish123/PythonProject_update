"""Instrument a shadow of qualified a4 DDR code; retain all functional sources."""
from pathlib import Path
import hashlib
import json
import re

D = Path(__file__).resolve().parent
R = D.parents[1]
O = D / "results"
O.mkdir(exist_ok=True)
base = R / "release/ddr_camera_hires_20261011"
qualification = json.loads((base / "build_qualification.json").read_text(encoding="utf-8-sig"))
assert qualification["simulations_passed"] and qualification["timing_passed"]
baseline = json.loads((base / "source_hashes.json").read_text(encoding="utf-8-sig"))
for path, digest in baseline.items():
    assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest, path
changed = {}
def load(relative):
    candidates = [Path(q) for q in baseline if Path(q).name == Path(relative).name]
    assert len(candidates) == 1, relative
    path = candidates[0]
    assert str(path) in baseline and hashlib.sha256(path.read_bytes()).hexdigest() == baseline[str(path)]
    changed[path] = path.read_text(encoding="utf-8-sig")
    return path
def change(path, before, after):
    assert changed[path].count(before) == 1, (path.name, before)
    changed[path] = changed[path].replace(before, after)

p = load("rtl/algo/marker_detector.v")
change(p, "output reg [11:0] x0,y0,x1,y1,x2,y2,x3,y3\n);", "output reg [11:0] x0,y0,x1,y1,x2,y2,x3,y3,\n output reg [191:0] diagnostic_snapshot\n);")
change(p, "state<=0;active<=0;bad<=0;corners_valid<=0;", "diagnostic_snapshot<=0;state<=0;active<=0;bad<=0;corners_valid<=0;")
change(p, "if(frame_end) begin\n    if(state!=0)", """if(frame_end) begin
    diagnostic_snapshot<={12'd0,good,nbad,(state!=0),!(frame_start||active),
      nc[0][15:0],nc[1][15:0],nc[2][15:0],nc[3][15:0],
      (nxmax[0]-nxmin[0]),(nxmax[1]-nxmin[1]),(nxmax[2]-nxmin[2]),(nxmax[3]-nxmin[3]),
      (nymax[0]-nymin[0]),(nymax[1]-nymin[1]),(nymax[2]-nymin[2]),(nymax[3]-nymin[3]),16'd0};
    if(state!=0)""")
p = load("vendor/b/rtl/b_rectifier.v")
change(p, "output wire out_valid, output wire [23:0] out_rgb,out_tag\n);", "output wire out_valid, output wire [23:0] out_rgb,out_tag,\n output wire [191:0] diagnostic_snapshot\n);")
change(p, "corners_valid,marker_reject,marker_dropped,marker_busy,x0,y0,x1,y1,x2,y2,x3,y3);", "corners_valid,marker_reject,marker_dropped,marker_busy,x0,y0,x1,y1,x2,y2,x3,y3,diagnostic_snapshot);")
p = load("rtl/top/frame_processor.v")
change(p, "output wire geometry_valid\n);", "output wire geometry_valid,\n output wire [3:0] diagnostic_state,output reg [7:0] diagnostic_error,\n output wire [191:0] diagnostic_marker\n);")
change(p, "assign busy=(state!=IDLE);", "assign busy=(state!=IDLE);\n assign diagnostic_state=state;")
change(p, "assign geometry_valid=1'b1;", "assign geometry_valid=1'b1;\n  assign diagnostic_marker=192'd0;")
change(p, ".marker_reject(reject_marker),.solver_reject(reject_solver)", ".diagnostic_snapshot(diagnostic_marker),.marker_reject(reject_marker),.solver_reject(reject_solver)")
change(p, "state<=IDLE;done<=0;error<=0;mode<=0;", "diagnostic_error<=0;state<=IDLE;done<=0;error<=0;mode<=0;")
change(p, "IDLE: if(start&&!fault)begin", "IDLE: if(start&&!fault)begin\n     diagnostic_error<=0;")
change(p, "if(out_tag!={dy,dx})begin error<=1;state<=IDLE;end", "if(out_tag!={dy,dx})begin diagnostic_error<=8'h08;error<=1;state<=IDLE;end")
change(p, "default:begin state<=IDLE;error<=1;end", "default:begin diagnostic_error<=8'h10;state<=IDLE;error<=1;end")
change(p, "state<=IDLE;error<=1;\n    if(watchdog", "diagnostic_error<=reject_marker?8'h01:reject_solver?8'h02:8'h04;\n    state<=IDLE;error<=1;\n    if(watchdog")
p = load("rtl/top/frame_session.v")
change(p, "output reg [31:0] good_frames,rejected_frames\n);", "output reg [31:0] good_frames,rejected_frames,\n    output wire [3:0] diagnostic_state\n);")
change(p, "assign publish_bank=write_bank;", "assign publish_bank=write_bank;\n    assign diagnostic_state=state;")
p = load("rtl/video/ddr_snapshot_capture.v")
change(p, "output wire fifo_wr_en,output reg [284:0] fifo_wr_data,input wire fifo_full", "output wire fifo_wr_en,output reg [284:0] fifo_wr_data,input wire fifo_full,\n output wire [95:0] diagnostic_snapshot")
change(p, "wire vs_rise=rx_vs&&!vs_d;", """wire vs_rise=rx_vs&&!vs_d;
 reg [15:0] diagnostic_good,diagnostic_bad,diagnostic_lines,diagnostic_packets;
 reg [23:0] diagnostic_samples;
 reg [7:0] diagnostic_flags;
 assign diagnostic_snapshot={diagnostic_good,diagnostic_bad,diagnostic_samples,diagnostic_lines,diagnostic_flags,diagnostic_packets};""")
change(p, "request_sync<=0;rx_complete_toggle<=0;capture_ok<=0;", "diagnostic_good<=0;diagnostic_bad<=0;diagnostic_samples<=0;diagnostic_lines<=0;diagnostic_flags<=0;diagnostic_packets<=0;\n   request_sync<=0;rx_complete_toggle<=0;capture_ok<=0;")
change(p, "if(finish_pending&&!packet_pending)begin", """if(finish_pending&&!packet_pending)begin
    if(finish_candidate&&!frame_bad&&!fifo_overflow)begin
     if(diagnostic_good!=16'hffff)diagnostic_good<=diagnostic_good+1'b1;
    end else if(diagnostic_bad!=16'hffff)diagnostic_bad<=diagnostic_bad+1'b1;
    diagnostic_samples<=sampled_pixels;diagnostic_lines<={3'd0,y_line_count};
    diagnostic_packets<=packet_word_addr[18:3];
    diagnostic_flags<={5'd0,finish_candidate,frame_bad,fifo_overflow};""")
p = load("rtl/memory/ddr_capture_writer.v")
change(p, "output reg complete_toggle,output reg capture_ok", "output reg complete_toggle,output reg capture_ok,\n output wire [63:0] diagnostic_snapshot")
change(p, "assign cmd_write=1'b1;", "assign cmd_write=1'b1;\n assign diagnostic_snapshot={packets_seen[23:0],packets_written[23:0],state,frame_bad,rx_ok_sync[2],rx_done_sync[2],complete_toggle,token,empty_quiet[7:0]};")
p = load("rtl/top/video_correct_ddr_core.v")
change(p, "input wire cmd_ready,rsp_valid,rsp_write,input wire [255:0] rsp_rdata", "input wire cmd_ready,rsp_valid,rsp_write,input wire [255:0] rsp_rdata,\n output wire [95:0] diagnostic_rx,output wire [127:0] diagnostic_proc,\n output reg [191:0] diagnostic_marker,output wire [63:0] diagnostic_ui")
change(p, "wire all_error=p_error||writer_fault||fault_sync[2];", """wire all_error=p_error||writer_fault||fault_sync[2];
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
 end""")
change(p, ".frame_error(session_error),.input_wait(input_wait)", ".diagnostic_state(session_state),.frame_error(session_error),.input_wait(input_wait)")
change(p, ".fifo_full(fifo_full),.rx_complete_toggle(rx_complete)", ".diagnostic_snapshot(diagnostic_rx),.fifo_full(fifo_full),.rx_complete_toggle(rx_complete)")
change(p, ".rsp_valid(cap_rsp),.rsp_write(cap_rsp_write),.complete_toggle(capture_ack)", ".diagnostic_snapshot(),.rsp_valid(cap_rsp),.rsp_write(cap_rsp_write),.complete_toggle(capture_ack)")
change(p, ".write_valid(wr_v),.write_ready(wr_ready),.write_addr(wr_a),.write_rgb(wr_rgb),.cycles(),.completed_pixels(),.geometry_valid());", ".write_valid(wr_v),.write_ready(wr_ready),.write_addr(wr_a),.write_rgb(wr_rgb),\n  .diagnostic_state(processor_state),.diagnostic_error(processor_error_code),.diagnostic_marker(marker_snapshot),\n  .cycles(processor_cycles),.completed_pixels(),.geometry_valid());")

change(p, ".cmd_valid(display_v),.cmd_ready(display_r),.cmd_addr(display_a),", ".diagnostic_snapshot(diagnostic_ui),.cmd_valid(display_v),.cmd_ready(display_r),.cmd_addr(display_a),")
p = load("rtl/video/ddr_result_display.v")
change(p, '(* ram_style="block", ramstyle="M20K" *) reg [255:0] line_mem0', '(* syn_ramstyle="block_ram" *) reg [255:0] line_mem0')
change(p, '(* ram_style="block", ramstyle="M20K" *) reg [255:0] line_mem1', '(* syn_ramstyle="block_ram" *) reg [255:0] line_mem1')
change(p, "output reg          underrun\n);", "output reg          underrun,\n    output wire [63:0] diagnostic_snapshot\n);")
change(p, "reg cmd_valid_r;", """reg cmd_valid_r;
    reg [15:0] diagnostic_row_cycles,diagnostic_last_cycles,diagnostic_max_cycles;
    reg [9:0] diagnostic_rows_done;
    wire [9:0] diagnostic_row=ui_line_row;
    wire [6:0] diagnostic_beat=burst_index;
    assign diagnostic_snapshot={diagnostic_last_cycles,diagnostic_max_cycles,diagnostic_rows_done,
        diagnostic_row,ui_state,diagnostic_beat,scan_active_ui[2],ui_req_seen,ui_ack_toggle};""")
change(p, "active_base<=BASE0; cmd_addr_r<=0; cmd_valid_r<=0;", "active_base<=BASE0; cmd_addr_r<=0; cmd_valid_r<=0;\n            diagnostic_row_cycles<=0;diagnostic_last_cycles<=0;diagnostic_max_cycles<=0;diagnostic_rows_done<=0;")
change(p, "case(ui_state)", "if(ui_state!=UI_IDLE && diagnostic_row_cycles!=16'hffff)diagnostic_row_cycles<=diagnostic_row_cycles+1'b1;\n            case(ui_state)")
change(p, "ui_line_gen<=req_gen;", "diagnostic_row_cycles<=0;ui_line_gen<=req_gen;")
change(p, "ui_ack_toggle<=ui_req_seen;ui_state<=UI_IDLE;", """ui_ack_toggle<=ui_req_seen;ui_state<=UI_IDLE;
                            diagnostic_last_cycles<=diagnostic_row_cycles;
                            if(diagnostic_row_cycles>diagnostic_max_cycles)diagnostic_max_cycles<=diagnostic_row_cycles;
                            if(diagnostic_rows_done!=10'h3ff)diagnostic_rows_done<=diagnostic_rows_done+1'b1;""")

p = load("rtl/top/video_correct_ddr_top.v")
change(p, "output wire hd_tx_pclk,output reg hd_tx_vs,hd_tx_hs,hd_tx_de,\n output reg [23:0] hd_tx_data,", "output wire hd_tx_pclk,hd_tx_vs,hd_tx_hs,hd_tx_de,\n output wire [23:0] hd_tx_data,")
change(p, "wire [23:0] rgb;", "wire [23:0] rgb;\n wire [95:0] debug_rx;wire [127:0] debug_proc;wire [191:0] debug_marker;wire [63:0] debug_ui;")
change(p, ".display_underrun(underrun),.selftest_passed(self_pass)", ".diagnostic_rx(debug_rx),.diagnostic_proc(debug_proc),.diagnostic_marker(debug_marker),.diagnostic_ui(debug_ui),\n  .display_underrun(underrun),.selftest_passed(self_pass)")
change(p, """always @(posedge pix_clk or negedge pix_rst)begin
  if(!pix_rst)begin hd_tx_hs<=0;hd_tx_vs<=0;hd_tx_de<=0;hd_tx_data<=0;end
  else begin hd_tx_hs<=hs;hd_tx_vs<=vs;hd_tx_de<=den;hd_tx_data<=rgb;end
 end""", """wire observe_request;
 wire [95:0] rx_snapshot;
 wire [319:0] proc_snapshot;
 wire [63:0] ui_snapshot;
 wire rx_observe_valid,rx_observe_busy,proc_observe_valid,proc_observe_busy,ui_observe_valid,ui_observe_busy;
 cdc_snapshot #(.WIDTH(96)) rx_observe(.src_clk(hd_rx_pclk),.src_reset_n(rx_rst),.src_data(debug_rx),
  .dst_clk(pix_clk),.dst_reset_n(pix_rst),.request(observe_request),.dst_data(rx_snapshot),.valid(rx_observe_valid),.busy(rx_observe_busy));
 cdc_snapshot #(.WIDTH(320)) proc_observe(.src_clk(sys_clk_27m),.src_reset_n(proc_rst),.src_data({debug_proc,debug_marker}),
  .dst_clk(pix_clk),.dst_reset_n(pix_rst),.request(observe_request),.dst_data(proc_snapshot),.valid(proc_observe_valid),.busy(proc_observe_busy));
 cdc_snapshot #(.WIDTH(64)) ui_observe(.src_clk(ui_clk),.src_reset_n(ui_rst),.src_data(debug_ui),
  .dst_clk(pix_clk),.dst_reset_n(pix_rst),.request(observe_request),.dst_data(ui_snapshot),.valid(ui_observe_valid),.busy(ui_observe_busy));
 wire [15:0] status_flags={clocks_ready,ddr_lock,ddr_ready,self_pass,self_fail,engine_fault,phy_fail,align_error,
  rx_done,tx_done,config_error,ack_error,image_valid,frame_error,input_wait,underrun};
 (* ASYNC_REG="TRUE" *) reg [15:0] flags_meta,flags_sync;
 always @(posedge pix_clk or negedge pix_rst)begin
  if(!pix_rst)begin flags_meta<=0;flags_sync<=0;end
  else begin flags_meta<=status_flags;flags_sync<=flags_meta;end
 end
 ddr_status_overlay diagnostic_display(.clk(pix_clk),.reset_n(pix_rst),.in_hs(hs),.in_vs(vs),.in_de(den),.in_rgb(rgb),
  .status_word({16'hD206,flags_sync,rx_snapshot,proc_snapshot,ui_snapshot}),.snapshot_request(observe_request),
  .out_hs(hd_tx_hs),.out_vs(hd_tx_vs),.out_de(hd_tx_de),.out_rgb(hd_tx_data));""")

flow = (R / "diagnostics/ddr_camera_hires_20261011/results/build.tcl").read_text(encoding="utf-8-sig")
for original, text in changed.items():
    target = O / original.name
    target.write_text(text, encoding="utf-8")
    old = f"add_design {{{original.as_posix()}}}"
    assert flow.count(old) == 1
    flow = flow.replace(old, f"add_design {{{target.as_posix()}}}")
cdc = O / "cdc_snapshot.v"
cdc.write_bytes((R / "vendor/c_current/01_design_code/cdc_snapshot.v").read_bytes())
overlay = D / "ddr_status_overlay.v"
flow = flow.replace("compile -top_module video_correct_ddr_top", f"add_design {{{cdc.as_posix()}}}\nadd_design {{{overlay.as_posix()}}}\ncompile -top_module video_correct_ddr_top")
(O / "build.tcl").write_text(flow, encoding="utf-8")
paths = [Path(match[1]) for line in flow.splitlines() if (match := re.fullmatch(r"add_design \{(.+)\}", line))]
paths += [R / "constr/board_ddr.fdc"]
(O / "source_hashes.json").write_text(json.dumps({str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}, indent=2) + "\n", encoding="utf-8")
print(f"Prepared independent DDR observer; {len(changed)} instrumented modules, all other compiled sources retained.")
