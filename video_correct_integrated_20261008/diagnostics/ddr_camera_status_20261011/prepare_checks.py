"""Exercise new diagnostics with valid frames, malformed capture and missing markers."""
from pathlib import Path
import json

D = Path(__file__).resolve().parent
R = D.parents[1]
O = D / "results"
tb = (R / "sim/tb_video_correct_ddr_core.sv").read_text(encoding="utf-8-sig")
before = "  proc_rst_n=0;rx_rst_n=0;ui_rst_n=0;pix_rst_n=0;rx_vs=0;rx_de=0;rx_rgb=0;"
assert tb.count(before) == 1
tb = tb.replace(before, """  if(dut.diagnostic_rx[79:64]==0)$fatal(1,"malformed capture not counted by actual RX diagnostic");
  begin : marker_rejection_probe
   integer rejected_before;
   rejected_before=rejected_frames;
   fork begin while(rejected_frames==rejected_before) send_frame(2,0);end
    begin wait(rejected_frames>rejected_before);end join_any disable fork;
   if(dut.last_failure!=8'h01)$fatal(1,"actual missing-marker rejection not reported: %h",dut.last_failure);
   if(good_frames!=2)$fatal(1,"marker-rejected frame published");
   compare_frame(0,1);wait(dut.display_ack==dut.pub_toggle);display_check(1);
  end
""" + before)
tb = tb.replace('$display("DDR_CORE_PASS', '$display("DDR_CORE_STATUS_PASS')
tb = tb.replace("vendor/b/vectors/", (R / "vendor/b/vectors").as_posix() + "/")
tb = tb.replace(".rsp_rdata(rsp_rdata));", ".rsp_rdata(rsp_rdata),.diagnostic_rx(),.diagnostic_proc(),.diagnostic_marker(),.diagnostic_ui());")
old_source_check = "   end else if(src_mem[chkbeat][chklane*32+:24]!==src0[chkbeat*8+chklane])"
assert tb.count(old_source_check) == 1
tb = tb.replace(old_source_check, """   end else if(good_frames==2)begin
    if(src_mem[chkbeat][chklane*32+:24]!==src2[chkbeat*8+chklane])$fatal(1,"source2 DDR snapshot mismatch");
   end else if(src_mem[chkbeat][chklane*32+:24]!==src0[chkbeat*8+chklane])""")
(O / "tb_video_correct_ddr_core.sv").write_text(tb, encoding="utf-8")
tb = (R / "vendor/b/sim/tb_marker_detector.sv").read_text(encoding="utf-8-sig")
tb = tb.replace("wire cv,reject,drop,busy;", "wire [191:0] marker_state;\n wire cv,reject,drop,busy;")
assert tb.count("busy,x0,y0,x1,y1,x2,y2,x3,y3);") == 1
tb = tb.replace("busy,x0,y0,x1,y1,x2,y2,x3,y3);", "busy,x0,y0,x1,y1,x2,y2,x3,y3,marker_state);")
tb = tb.replace("frame(0,0,0);frame(0,0,0);", """frame(0,0,0);
  if(marker_state[175:112]!={16'd16,16'd16,16'd16,16'd16}||marker_state[191:176]!=16'h0008)
   $fatal(1,"actual inclusive marker snapshot incorrect");
  frame(0,0,0);""")
tb = tb.replace("frame(1,0,0);repeat(5)", "frame(1,0,0);if(marker_state[143:128]!=15||marker_state[179])$fatal(1,\"missing yellow threshold report\");repeat(5)")
tb = tb.replace("MARKER_PASS", "MARKER_STATUS_PASS")
(O / "tb_marker_detector.sv").write_text(tb, encoding="utf-8")
capture_tb = (R / "sim/tb_ddr_capture.sv").read_text(encoding="utf-8-sig")
assert capture_tb.count(".fifo_full(fifo_full));") == 1
capture_tb = capture_tb.replace(".fifo_full(fifo_full));", ".fifo_full(fifo_full),.diagnostic_snapshot());")
capture_tb = capture_tb.replace(".capture_ok(capture_ok));", ".capture_ok(capture_ok),.diagnostic_snapshot());")
(O / "tb_ddr_capture.sv").write_text(capture_tb, encoding="utf-8")
manifest = json.loads((O / "source_hashes.json").read_text(encoding="utf-8-sig"))
rtl = [Path(p) for p in manifest if p.endswith(".v") and "/ddr3_ip/" not in p.replace("\\", "/") and "/ip/" not in p.replace("\\", "/")]
cases = {
    "tb_ddr_status_overlay": ("DDR_STATUS_OVERLAY_PASS", [D / "ddr_status_overlay.v", D / "tb_ddr_status_overlay.sv"]),
    "tb_marker_detector": ("MARKER_STATUS_PASS", [O / "marker_detector.v", R / "vendor/b/rtl/unsigned_div_seq.v", O / "tb_marker_detector.sv"]),
    "tb_ddr_capture": ("DDR_CAPTURE_PASS", rtl + [O / "tb_ddr_capture.sv"]),
    "tb_video_correct_ddr_core": ("DDR_CORE_STATUS_PASS", rtl + [O / "tb_video_correct_ddr_core.sv"]),
}
for name, (marker, paths) in cases.items():
    lines = ["onerror {quit -f -code 1}", f"transcript file {{{(O / (name + '.transcript.log')).as_posix()}}}",
        f"if {{![file isdirectory work_{name}]}} {{vlib work_{name}}}", f"vmap work_{name} work_{name}",
        f"vlog -sv -work work_{name} " + " ".join("{" + p.as_posix() + "}" for p in paths),
        f"vsim -c -voptargs=+acc -wlf {{{(O / (name + '.wlf')).as_posix()}}} work_{name}.{name}",
        "onfinish stop", "run -all",
        f"set pass_bit [examine -value -radix binary -noshowbase sim:/{name}/test_passed]",
        "if {[llength $pass_bit] != 1 || [lindex $pass_bit 0] ne \"1\"} {quit -f -code 1}",
        "puts \"VERIFIED_PASS_BIT=1\"", "quit -f -code 0"]
    (O / (name + ".do")).write_text("\n".join(lines) + "\n", encoding="utf-8")
(O / "simulation_cases.json").write_text(json.dumps({name: v[0] for name, v in cases.items()}, indent=2) + "\n", encoding="utf-8")
print("Prepared actual diagnostic regressions with snapshot inclusion and rejection/retention checks.")
