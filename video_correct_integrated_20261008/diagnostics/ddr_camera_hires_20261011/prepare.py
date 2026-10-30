"""Prepare a high-detail clone; keep the physically verified 320x452 release."""
from pathlib import Path
import hashlib
import json
import re

D = Path(__file__).resolve().parent
R = D.parents[1]
O = D / "results"
O.mkdir(exist_ok=True)
base = R / "release/ddr_camera_reconnect_20261011"
qualification = json.loads((base / "build_qualification.json").read_text(encoding="utf-8-sig"))
assert qualification["simulations_passed"] and qualification["timing_passed"]
baseline = json.loads((base / "source_hashes.json").read_text(encoding="utf-8-sig"))
for path, digest in baseline.items():
    assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest, path
top_path = R / "rtl/top/video_correct_ddr_top.v"
top = top_path.read_text(encoding="utf-8-sig")
assert top.count("video_correct_ddr_core core(") == 1
top = top.replace("video_correct_ddr_core core(", "video_correct_ddr_core #(.SRC_W(960),.SRC_H(540),.OUT_W(640),.OUT_H(904),.SCALE(1),.FIFO_ADDR_BITS(10)) core(")
(O / top_path.name).write_text(top, encoding="utf-8")
display_path = R / "rtl/video/ddr_result_display.v"
display = display_path.read_text(encoding="utf-8-sig")
assert display.count("localparam BURSTS_PER_ROW=OUT_W/8;") == 1
display = display.replace("localparam BURSTS_PER_ROW=OUT_W/8;", """localparam BURSTS_PER_ROW=OUT_W/8;
    // Include the one-past-last-row sentinel in the mailbox coordinate width.
    localparam ROW_BITS=(OUT_H<2)?1:$clog2(OUT_H+1);
    localparam BURST_BITS=(BURSTS_PER_ROW<2)?1:$clog2(BURSTS_PER_ROW);""")
assert display.count("[8:0]") == 8
display = display.replace("[8:0]", "[ROW_BITS-1:0]")
assert display.count("reg [5:0] burst_index;") == 1
display = display.replace("reg [5:0] burst_index;", "reg [BURST_BITS-1:0] burst_index;")
display = display.replace("reg [23:0] line_mem0[0:OUT_W-1];", "reg [255:0] line_mem0[0:BURSTS_PER_ROW-1];")
display = display.replace("reg [23:0] line_mem1[0:OUT_W-1];", "reg [255:0] line_mem1[0:BURSTS_PER_ROW-1];")
old_write = """                        if(ui_line_row[0]) line_mem1[burst_index*8+pixel_index]<=beat_data[pixel_index*32 +: 24];
                        else               line_mem0[burst_index*8+pixel_index]<=beat_data[pixel_index*32 +: 24];
                        if(pixel_index==7) begin
                            if(burst_index==BURSTS_PER_ROW-1) begin
                                ui_ack_toggle<=ui_req_seen;
                                ui_state<=UI_IDLE;
                            end else begin
                                burst_index<=burst_index+1'b1;
                                ui_state<=UI_CMD;
                            end
                        end else pixel_index<=pixel_index+1'b1;"""
assert display.count(old_write) == 1
display = display.replace(old_write, """                        // Store all eight padded RGB888 words on one UI clock.
                        if(ui_line_row[0]) line_mem1[burst_index]<=beat_data;
                        else               line_mem0[burst_index]<=beat_data;
                        if(burst_index==BURSTS_PER_ROW-1) begin
                            ui_ack_toggle<=ui_req_seen;ui_state<=UI_IDLE;
                        end else begin
                            burst_index<=burst_index+1'b1;ui_state<=UI_CMD;
                        end""")
display = display.replace("    reg [2:0] pixel_index;\n", "")
display = display.replace(" pixel_index<=0;", "")
display = display.replace("                        pixel_index<=0;\n", "")
assert display.count("reg [23:0] pixel_q;") == 1
display = display.replace("reg [23:0] pixel_q;", "reg [255:0] line_word_q;\n    reg [2:0] line_lane_q;\n    wire [23:0] pixel_q=line_word_q[line_lane_q*32 +: 24];")
display = display.replace("line_ok<=0; pixel_q<=0;", "line_ok<=0; line_word_q<=0;line_lane_q<=0;")
old_read = """            if(active_window) begin
                if(cur_y[0]) begin
                    if(line_ok) pixel_q<=line_mem1[cur_x]; else pixel_q<=0;
                end else begin
                    if(line_ok) pixel_q<=line_mem0[cur_x]; else pixel_q<=0;
                end
            end else begin
                pixel_q<=0;
            end"""
assert display.count(old_read) == 1
display = display.replace(old_read, """            line_lane_q<=cur_x[2:0];
            if(active_window && line_ok) begin
                if(cur_y[0]) line_word_q<=line_mem1[cur_x>>3];
                else line_word_q<=line_mem0[cur_x>>3];
            end else line_word_q<=0;""")
assert "pixel_q<=" not in display and "pixel_index" not in display
display = display.replace("// DDR-backed display for the completed 320x452 result frame.", "// DDR-backed, parameter-sized display for a completed result frame.")
display = display.replace("// Two 320x24 line buffers. UI writes one pixel/cycle; pixel domain reads\n    // synchronously. No write request is declared complete until all 320\n    // pixels of its line have been written.", "// Two packed line buffers. UI stores eight padded RGB words per write;\n    // pixel domain reads a word synchronously and selects its aligned lane.\n    // A row becomes visible only after its final complete beat is stored.")
display = display.replace("// UI reader: serialized single-beat commands, then eight sequential\n    // writes to the selected line buffer for each returned 256-bit beat.", "// UI reader: serialized single-beat commands, one packed-memory write\n    // for each returned 256-bit beat.")
display = display.replace("// 320 32-bit words per row; a 256-bit command advances 8 words.", "// OUT_W padded RGB words per row; each command advances eight words.")
(O / display_path.name).write_text(display, encoding="utf-8")
processor_path = R / "rtl/top/frame_processor.v"
processor = processor_path.read_text(encoding="utf-8-sig")
old_ports = ".params_pending(pending),.geometry_valid(geometry_valid),"
assert processor.count(old_ports) == 1
processor = processor.replace(old_ports, old_ports + "\n   .corners_valid(),.marker_dropped(),.x0(),.y0(),.x1(),.y1(),.x2(),.y2(),.x3(),.y3(),.stale_frames(),")
(O / processor_path.name).write_text(processor, encoding="utf-8")
flow = (R / "diagnostics/ddr_camera_reconnect_20261011/results/build.tcl").read_text(encoding="utf-8-sig")
for original in [top_path, display_path, processor_path]:
    old = f"add_design {{{original.as_posix()}}}"
    assert flow.count(old) == 1
    flow = flow.replace(old, f"add_design {{{(O / original.name).as_posix()}}}")
(O / "build.tcl").write_text(flow, encoding="utf-8")
paths = [Path(match[1]) for line in flow.splitlines() if (match := re.fullmatch(r"add_design \{(.+)\}", line))]
paths += [R / "constr/board_ddr.fdc"]
(O / "source_hashes.json").write_text(json.dumps({str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}, indent=2) + "\n", encoding="utf-8")
config = {"input": [1920,1080],"source": [960,540],"output": [640,904],"display": [1920,1080],"scale": 1,
    "window": {"x":640,"y":88,"width":640,"height":904},"capture_fifo_packets":1024,
    "source_bytes":960*540*4,"result_bank_bytes":640*904*4,"source_base_byte":0,"bank0_base_byte":4194304,"bank1_base_byte":8388608,
    "baseline_image_sha256":"a4bd7f42732c100b598cb974e03477877aab4032e39f6de558bb245d666e232e",
    "physical_acceptance":False,"note":"True 640x904 result in the same screen window; preserved baseline remains loaded until simulations and timing qualify the new clone."}
assert config["source_bytes"] < config["bank0_base_byte"]
assert config["bank0_base_byte"] + config["result_bank_bytes"] < config["bank1_base_byte"]
assert config["bank1_base_byte"] + config["result_bank_bytes"] < 16515072
(O / "configuration.json").write_text(json.dumps(config,indent=2)+"\n",encoding="utf-8")
print("Prepared independent higher-detail parameters and generalized row/beat counters; known-good release retained.")
