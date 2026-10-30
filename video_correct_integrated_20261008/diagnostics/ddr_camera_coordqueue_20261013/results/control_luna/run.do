onerror {quit -f -code 1}
transcript file {control_luna.transcript.log}
if {![file isdirectory work]} {vlib work}
vmap work work
vlog -sv -work work {C:/D/FPGA/video_correct_integrated_20261008/vendor/b/rtl/b_rectifier.v} {C:/D/FPGA/video_correct_integrated_20261008/vendor/b/rtl/bilinear_interp.v} {C:/D/FPGA/video_correct_integrated_20261008/vendor/b/rtl/homography_solver.v} {C:/D/FPGA/video_correct_integrated_20261008/vendor/b/rtl/perspective_coord.v} {C:/D/FPGA/video_correct_integrated_20261008/vendor/b/rtl/perspective_core.v} {C:/D/FPGA/video_correct_integrated_20261008/vendor/b/rtl/scaled_div_pipe.v} {C:/D/FPGA/video_correct_integrated_20261008/vendor/b/rtl/signed_div_seq.v} {C:/D/FPGA/video_correct_integrated_20261008/vendor/b/rtl/unsigned_div_seq.v} {C:/D/FPGA/video_correct_integrated_20261008/rtl/algo/marker_detector.v} {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_coordqueue_20261013/results/frame_processor.v} {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_coordqueue_20261013/tb_coord_queue_control.sv}
vsim -c -voptargs=+acc -wlf control_luna.wlf work.tb_coord_queue_control
onfinish stop
run -all
set pass_bit [examine -value -radix binary -noshowbase sim:/tb_coord_queue_control/test_passed]
if {[llength $pass_bit]!=1 || [lindex $pass_bit 0] ne "1"} {quit -f -code 1}
puts "VERIFIED_PASS_BIT=1"
quit -f -code 0
