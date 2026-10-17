"""Reproduce late-row black scanout under a deliberately slow DDR response model."""
from pathlib import Path

D=Path(__file__).resolve().parent
R=D.parents[1]
O=D/"results"
O.mkdir(exist_ok=True)
status=R/"diagnostics/ddr_camera_hires_status_20261011/results"
text=(status/"tb_native_display.sv").read_text(encoding="utf-8-sig")
text=text.replace('module tb_native_display #(parameter CONTENTIOUS=0);','module tb_hires_deadline_probe;\n localparam CONTENTIOUS=0;')
text=text.replace('reg previous_vs=0,test_passed=0;', 'integer correct_pixels=0,black_pixels=0;\n reg previous_vs=0,test_passed=0;')
text=text.replace('delay_count<=4+(ui_cycle%3)', 'delay_count<=28+(ui_cycle%3)')
before='''   if(rgb!==encode_pixel(frame_bank,vd2-Y0,hd2-X0))$fatal(1,"native row/word/lane mismatch bank=%0d x=%0d y=%0d got=%h expected=%h",frame_bank,hd2-X0,vd2-Y0,rgb,encode_pixel(frame_bank,vd2-Y0,hd2-X0));'''
after='''   if(rgb===encode_pixel(frame_bank,vd2-Y0,hd2-X0))correct_pixels=correct_pixels+1;
   else if(rgb===24'd0)black_pixels=black_pixels+1;
   else $fatal(1,"late display output an incorrect/stale row instead of black");'''
assert text.count(before)==1
text=text.replace(before,after)
text=text.replace('if(underrun)$fatal(1,"native display underflow");', 'if(!underrun || black_pixels<OW*(OH/2))$fatal(1,"slow model did not reproduce missing rows");')
start=text.index('  // Change the pending frame during active scan.')
end=text.index('  test_passed=1;',start)
text=text[:start]+'''  wait(completed_frames>=1);
  if(diagnostics[47:32]<=1852)$fatal(1,"row timing did not report service time beyond one physical scan line");
'''+text[end:]
start=text.index('  test_passed=1;')
end=text.index('\n end',start)
text=text[:start]+'''  test_passed=1;$display("DDR_DEADLINE_REPRODUCED correct_pixels=%0d black_pixels=%0d max_row_cycles=%0d one_line_budget=1852 hypothetical_memory_only=1",correct_pixels,black_pixels,diagnostics[47:32]);$finish;'''+text[end:]
(O/"tb_hires_deadline_probe.sv").write_text(text,encoding="utf-8")
paths=[status/"ddr_result_display.v",R/"vendor/c_current/01_design_code/video_timing_vtc.v",O/"tb_hires_deadline_probe.sv"]
lines=["onerror {quit -f -code 1}",f"transcript file {{{(O/'probe.transcript.log').as_posix()}}}",
    "if {![file isdirectory work]} {vlib work}","vmap work work",
    "vlog -sv "+" ".join("{"+p.as_posix()+"}" for p in paths),
    "vsim -c -voptargs=+acc work.tb_hires_deadline_probe","onfinish stop","run -all",
    "set pass_bit [examine -value -radix binary -noshowbase sim:/tb_hires_deadline_probe/test_passed]",
    'if {[llength $pass_bit]!=1 || [lindex $pass_bit 0] ne "1"} {quit -f -code 1}',
    'puts "VERIFIED_PASS_BIT=1"',"quit -f -code 0"]
(O/"probe.do").write_text("\n".join(lines)+"\n",encoding="utf-8")
print("Prepared hypothetical delayed-response reproduction; actual DDR latency still requires board measurements.")
