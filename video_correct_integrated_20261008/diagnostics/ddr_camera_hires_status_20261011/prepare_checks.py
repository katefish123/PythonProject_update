"""Regress actual instrumentation and the unchanged full high-detail pipeline."""
from pathlib import Path
import json
import shutil

D=Path(__file__).resolve().parent
R=D.parents[1]
O=D/"results"
old=R/"diagnostics/ddr_camera_status_20261011"
high=R/"diagnostics/ddr_camera_hires_20261011"
text=(old/"prepare_checks.py").read_text(encoding="utf-8-sig")
exec(compile(text,str(old/"prepare_checks.py"),"exec"),{"__file__":str(D/"prepare_checks.py"),"__name__":"__main__"})
cases=json.loads((O/"simulation_cases.json").read_text(encoding="utf-8-sig"))
manifest=json.loads((O/"source_hashes.json").read_text(encoding="utf-8-sig"))
rtl=[Path(p) for p in manifest if p.endswith(".v") and "/ddr3_ip/" not in p.replace("\\","/") and "/ip/" not in p.replace("\\","/")]
native=(high/"tb_native_display.sv").read_text(encoding="utf-8-sig")
native=native.replace("wire ack,cmd_valid;", "wire [63:0] diagnostics;\n wire ack,cmd_valid;")
native=native.replace(".underrun(underrun));", ".underrun(underrun),.diagnostic_snapshot(diagnostics));")
native=native.replace('test_passed=1;$display("NATIVE_DISPLAY_PASS',
    'if(diagnostics[31:22]==0 || diagnostics[63:48]==0 || diagnostics[47:32]<diagnostics[63:48])$fatal(1,"invalid actual row timing snapshot");\n  test_passed=1;$display("NATIVE_DISPLAY_PASS')
(O/"tb_native_display.sv").write_text(native,encoding="utf-8")
capture=(high/"tb_native_capture.sv").read_text(encoding="utf-8-sig")
capture=capture.replace(".fifo_full(full));", ".fifo_full(full),.diagnostic_snapshot());")
capture=capture.replace(".capture_ok(good));", ".capture_ok(good),.diagnostic_snapshot());")
(O/"tb_native_capture.sv").write_text(capture,encoding="utf-8")
full=(high/"results/tb_ddr_full_frame.sv").read_text(encoding="utf-8-sig")
full=full.replace(".geometry_valid(geometry_valid));", ".geometry_valid(geometry_valid),.diagnostic_state(),.diagnostic_error(),.diagnostic_marker());")
for name in ["source_960x540.hex","expected_640x904.hex"]:
    shutil.copyfile(high/"results"/name,O/name)
    full=full.replace((high/"results"/name).as_posix(),(O/name).as_posix())
(O/"tb_ddr_full_frame.sv").write_text(full,encoding="utf-8")
extras={
 "tb_native_display":("NATIVE_DISPLAY_PASS",[O/"ddr_result_display.v",R/"vendor/c_current/01_design_code/video_timing_vtc.v",O/"tb_native_display.sv"]),
 "tb_native_display_stress":("NATIVE_DISPLAY_PASS",[O/"ddr_result_display.v",R/"vendor/c_current/01_design_code/video_timing_vtc.v",O/"tb_native_display.sv"]),
 "tb_native_capture":("NATIVE_CAPTURE_PASS",rtl+[O/"tb_native_capture.sv"]),
 "tb_ddr_full_frame":("DDR_FULL_FRAME_PASS",rtl+[O/"tb_ddr_full_frame.sv"]),
}
for name,(marker,paths) in extras.items():
    top="tb_native_display" if name=="tb_native_display_stress" else name
    generic="-gCONTENTIOUS=1 " if name=="tb_native_display_stress" else ""
    lines=["onerror {quit -f -code 1}",f"transcript file {{{(O/(name+'.transcript.log')).as_posix()}}}",
      f"if {{![file isdirectory work_{name}]}} {{vlib work_{name}}}",f"vmap work_{name} work_{name}",
      f"vlog -sv -work work_{name} "+" ".join("{"+p.as_posix()+"}" for p in paths),
      f"vsim -c -voptargs=+acc -wlf {{{(O/(name+'.wlf')).as_posix()}}} {generic}work_{name}.{top}","onfinish stop","run -all",
      f"set pass_bit [examine -value -radix binary -noshowbase sim:/{top}/test_passed]",
      'if {[llength $pass_bit]!=1 || [lindex $pass_bit 0] ne "1"} {quit -f -code 1}',
      'puts "VERIFIED_PASS_BIT=1"',"quit -f -code 0"]
    (O/(name+".do")).write_text("\n".join(lines)+"\n",encoding="utf-8")
    cases[name]=marker
(O/"simulation_cases.json").write_text(json.dumps(cases,indent=2)+"\n",encoding="utf-8")
print("Prepared eight observer regressions including full native source, result, rows and timing counters.")
