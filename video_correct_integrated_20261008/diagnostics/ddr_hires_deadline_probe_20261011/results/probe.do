onerror {quit -f -code 1}
transcript file {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_hires_deadline_probe_20261011/results/probe.transcript.log}
if {![file isdirectory work]} {vlib work}
vmap work work
vlog -sv {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_hires_status_20261011/results/ddr_result_display.v} {C:/D/FPGA/video_correct_integrated_20261008/vendor/c_current/01_design_code/video_timing_vtc.v} {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_hires_deadline_probe_20261011/results/tb_hires_deadline_probe.sv}
vsim -c -voptargs=+acc work.tb_hires_deadline_probe
onfinish stop
run -all
set pass_bit [examine -value -radix binary -noshowbase sim:/tb_hires_deadline_probe/test_passed]
if {[llength $pass_bit]!=1 || [lindex $pass_bit 0] ne "1"} {quit -f -code 1}
puts "VERIFIED_PASS_BIT=1"
quit -f -code 0
