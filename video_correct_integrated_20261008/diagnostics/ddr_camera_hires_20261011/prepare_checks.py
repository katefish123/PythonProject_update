"""Check old behavior, native HD row addressing, memory ownership and full pixels."""
from pathlib import Path
import json

D=Path(__file__).resolve().parent
R=D.parents[1]
O=D/"results"
manifest=json.loads((O/"source_hashes.json").read_text(encoding="utf-8-sig"))
rtl=[Path(p) for p in manifest if p.endswith(".v") and "/ddr3_ip/" not in p.replace("\\","/") and "/ip/" not in p.replace("\\","/")]
(O/"tb_ddr_display.sv").write_bytes((R/"sim/tb_ddr_display.sv").read_bytes())
core=(R/"sim/tb_video_correct_ddr_core.sv").read_text(encoding="utf-8-sig")
core=core.replace("vendor/b/vectors/",(R/"vendor/b/vectors").as_posix()+"/")
(O/"tb_video_correct_ddr_core.sv").write_text(core,encoding="utf-8")
full=(R/"sim/tb_ddr_full_frame.sv").read_text(encoding="utf-8-sig")
full=full.replace("SRC_W=640,SRC_H=480,OUT_W=320,OUT_H=452", "SRC_W=960,SRC_H=540,OUT_W=640,OUT_H=904")
full=full.replace("28'h0018000", "28'h0100000")
full=full.replace("write_addr==319 || write_addr==320", "write_addr==OUT_W-1 || write_addr==OUT_W")
full=full.replace("results/ddr_fixture/source_640x480.hex",(O/"source_960x540.hex").as_posix())
full=full.replace("results/ddr_fixture/expected_320x452.hex",(O/"expected_640x904.hex").as_posix())
full=full.replace("#1200000000", "#4000000000.0")
(O/"tb_ddr_full_frame.sv").write_text(full,encoding="utf-8")
cases={
 "tb_ddr_display":("DDR_DISPLAY_PASS",rtl+[O/"tb_ddr_display.sv"]),
 "tb_native_display":("NATIVE_DISPLAY_PASS",[O/"ddr_result_display.v",R/"vendor/c_current/01_design_code/video_timing_vtc.v",D/"tb_native_display.sv"]),
 "tb_video_correct_ddr_core":("DDR_CORE_PASS",rtl+[O/"tb_video_correct_ddr_core.sv"]),
 "tb_ddr_full_frame":("DDR_FULL_FRAME_PASS",rtl+[O/"tb_ddr_full_frame.sv"]),
 "tb_native_capture":("NATIVE_CAPTURE_PASS",rtl+[D/"tb_native_capture.sv"]),
 "tb_native_display_stress":("NATIVE_DISPLAY_PASS",[O/"ddr_result_display.v",R/"vendor/c_current/01_design_code/video_timing_vtc.v",D/"tb_native_display.sv"]),
}
for name,(marker,paths) in cases.items():
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
(O/"simulation_cases.json").write_text(json.dumps({k:v[0] for k,v in cases.items()},indent=2)+"\n",encoding="utf-8")
print("Prepared full native dimensions and independent whole-frame RGB regression.")
