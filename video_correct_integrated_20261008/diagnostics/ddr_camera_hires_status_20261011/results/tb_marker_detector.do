onerror {quit -f -code 1}
transcript file {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_hires_status_20261011/results/tb_marker_detector.transcript.log}
if {![file isdirectory work_tb_marker_detector]} {vlib work_tb_marker_detector}
vmap work_tb_marker_detector work_tb_marker_detector
vlog -sv -work work_tb_marker_detector {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_hires_status_20261011/results/marker_detector.v} {C:/D/FPGA/video_correct_integrated_20261008/vendor/b/rtl/unsigned_div_seq.v} {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_hires_status_20261011/results/tb_marker_detector.sv}
vsim -c -voptargs=+acc -wlf {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_hires_status_20261011/results/tb_marker_detector.wlf} work_tb_marker_detector.tb_marker_detector
onfinish stop
run -all
set pass_bit [examine -value -radix binary -noshowbase sim:/tb_marker_detector/test_passed]
if {[llength $pass_bit] != 1 || [lindex $pass_bit 0] ne "1"} {quit -f -code 1}
puts "VERIFIED_PASS_BIT=1"
quit -f -code 0
