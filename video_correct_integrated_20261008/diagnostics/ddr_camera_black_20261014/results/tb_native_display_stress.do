onerror {quit -f -code 1}
transcript file {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/results/tb_native_display_stress.transcript.log}
if {![file isdirectory work_tb_native_display_stress]} {vlib work_tb_native_display_stress}
vmap work_tb_native_display_stress work_tb_native_display_stress
vlog -sv -work work_tb_native_display_stress {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/src/diagnostics/ddr_camera_hires_rowtrain_20261013/results/ddr_result_display.v} {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/src/vendor/c_current/01_design_code/video_timing_vtc.v} {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/results/tb_native_display.sv}
vsim -c -voptargs=+acc -wlf {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/results/tb_native_display_stress.wlf} -gCONTENTIOUS=1 work_tb_native_display_stress.tb_native_display
onfinish stop
run -all
set pass_bit [examine -value -radix binary -noshowbase sim:/tb_native_display/test_passed]
if {[llength $pass_bit]!=1 || [lindex $pass_bit 0] ne "1"} {quit -f -code 1}
puts "VERIFIED_PASS_BIT=1"
quit -f -code 0
