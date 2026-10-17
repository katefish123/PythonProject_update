onerror {quit -f -code 1}
transcript file {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/results/tb_hires_read_ahead_control.transcript.log}
if {![file isdirectory work_tb_hires_read_ahead_control]} {vlib work_tb_hires_read_ahead_control}
vmap work_tb_hires_read_ahead_control work_tb_hires_read_ahead_control
vlog -sv -work work_tb_hires_read_ahead_control {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/src/diagnostics/ddr_camera_hires_rowtrain_20261013/results/ddr_word_engine.v} {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/src/diagnostics/ddr_camera_hires_rowtrain_20261013/results/ddr_result_display.v} {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/src/rtl/memory/ddr_arbiter3.v} {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/src/vendor/c_current/01_design_code/video_timing_vtc.v} {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/results/tb_hires_read_ahead_display.sv}
vsim -c -voptargs=+acc -wlf {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/results/tb_hires_read_ahead_control.wlf} -gREAD_AHEAD=0 -gEXPECT_UNDERRUN=1 work_tb_hires_read_ahead_control.tb_hires_read_ahead_display
onfinish stop
run -all
set pass_bit [examine -value -radix binary -noshowbase sim:/tb_hires_read_ahead_display/test_passed]
if {[llength $pass_bit]!=1 || [lindex $pass_bit 0] ne "1"} {quit -f -code 1}
puts "VERIFIED_PASS_BIT=1"
quit -f -code 0
