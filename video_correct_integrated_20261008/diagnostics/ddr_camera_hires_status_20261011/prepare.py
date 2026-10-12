"""Observe the qualified high-detail image without altering retained releases."""
from pathlib import Path
import shutil

D = Path(__file__).resolve().parent
R = D.parents[1]
O = D / "results"
O.mkdir(exist_ok=True)
old = R / "diagnostics/ddr_camera_status_20261011"
text = (old / "prepare.py").read_text(encoding="utf-8-sig")
text = text.replace('base = R / "release/ddr_camera_reconnect_20261011"',
                    'base = R / "release/ddr_camera_hires_20261011"')
before = '    path = R / relative\n    assert str(path) in baseline'
after = ('    candidates = [Path(q) for q in baseline if Path(q).name == Path(relative).name]\n'
         '    assert len(candidates) == 1, relative\n'
         '    path = candidates[0]\n    assert str(path) in baseline')
assert text.count(before) == 1
text = text.replace(before, after)
# The qualified high-detail processor already connects the unused B outputs.
duplicate_ports = 'change(p, ".params_pending(pending),.geometry_valid(geometry_valid),", ".params_pending(pending),.geometry_valid(geometry_valid),\\n   .corners_valid(),.marker_dropped(),.x0(),.y0(),.x1(),.y1(),.x2(),.y2(),.x3(),.y3(),.stale_frames(),")\n'
assert text.count(duplicate_ports) == 1
text = text.replace(duplicate_ports, '')
text = text.replace('diagnostics/ddr_camera_reconnect_20261011/results/build.tcl',
                    'diagnostics/ddr_camera_hires_20261011/results/build.tcl')
text = text.replace('.diagnostic_snapshot(diagnostic_ui),.rsp_valid(cap_rsp)',
                    '.diagnostic_snapshot(),.rsp_valid(cap_rsp)')
# The last 64 bits describe the real display fetcher rather than RX drain.
insert = r'''
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
'''
anchor = 'p = load("rtl/top/video_correct_ddr_top.v")'
assert text.count(anchor) == 1
text = text.replace(anchor, insert + '\n' + anchor)
text = text.replace("16'hD205", "16'hD206")
(D / "prepared_instrumentation.py").write_text(text, encoding="utf-8")
shutil.copyfile(old / "ddr_status_overlay.v", D / "ddr_status_overlay.v")
shutil.copyfile(old / "tb_ddr_status_overlay.sv", D / "tb_ddr_status_overlay.sv")
exec(compile(text, str(D / "prepared_instrumentation.py"), "exec"),
     {"__file__": str(D / "prepared_instrumentation.py"), "__name__": "__main__"})
