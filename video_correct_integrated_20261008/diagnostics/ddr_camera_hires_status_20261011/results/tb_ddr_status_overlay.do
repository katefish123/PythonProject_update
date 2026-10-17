onerror {quit -f -code 1}
transcript file {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_hires_status_20261011/results/tb_ddr_status_overlay.transcript.log}
if {![file isdirectory work_tb_ddr_status_overlay]} {vlib work_tb_ddr_status_overlay}
vmap work_tb_ddr_status_overlay work_tb_ddr_status_overlay
vlog -sv -work work_tb_ddr_status_overlay {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_hires_status_20261011/ddr_status_overlay.v} {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_hires_status_20261011/tb_ddr_status_overlay.sv}
vsim -c -voptargs=+acc -wlf {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_hires_status_20261011/results/tb_ddr_status_overlay.wlf} work_tb_ddr_status_overlay.tb_ddr_status_overlay
onfinish stop
run -all
set pass_bit [examine -value -radix binary -noshowbase sim:/tb_ddr_status_overlay/test_passed]
if {[llength $pass_bit] != 1 || [lindex $pass_bit 0] ne "1"} {quit -f -code 1}
puts "VERIFIED_PASS_BIT=1"
quit -f -code 0
