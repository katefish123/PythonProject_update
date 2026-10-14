onerror {quit -f -code 1}
onbreak {resume}
vlib work_black_b
vmap work_black_b work_black_b
vlog -work work_black_b {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/b_algorithm/rtl/b_rectifier.v}
vlog -work work_black_b {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/b_algorithm/rtl/bilinear_interp.v}
vlog -work work_black_b {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/b_algorithm/rtl/homography_solver.v}
vlog -work work_black_b {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/b_algorithm/rtl/marker_detector.v}
vlog -work work_black_b {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/b_algorithm/rtl/perspective_coord.v}
vlog -work work_black_b {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/b_algorithm/rtl/perspective_core.v}
vlog -work work_black_b {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/b_algorithm/rtl/scaled_div_pipe.v}
vlog -work work_black_b {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/b_algorithm/rtl/signed_div_seq.v}
vlog -work work_black_b {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/b_algorithm/rtl/unsigned_div_seq.v}
vlog -work work_black_b {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/b_algorithm/examples/b_rectifier_instance.v}
vlog -sv -work work_black_b {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/b_algorithm/sim/tb_b_integration.sv}
vlog -sv -work work_black_b {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/b_algorithm/sim/tb_b_rectifier.sv}
vlog -sv -work work_black_b {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/b_algorithm/sim/tb_bilinear_interp.sv}
vlog -sv -work work_black_b {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/b_algorithm/sim/tb_cache_contract.sv}
vlog -sv -work work_black_b {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/b_algorithm/sim/tb_homography_solver.sv}
vlog -sv -work work_black_b {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/b_algorithm/sim/tb_marker_config.sv}
vlog -sv -work work_black_b {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/b_algorithm/sim/tb_marker_detector.sv}
vlog -sv -work work_black_b {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/b_algorithm/sim/tb_perspective_coord.sv}
vlog -sv -work work_black_b {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014/b_algorithm/sim/tb_request_boundaries.sv}
vsim -voptargs=+acc work_black_b.tb_perspective_coord
onfinish stop
run -all
set p [examine -value -radix binary -noshowbase sim:/tb_perspective_coord/test_passed]
if {[llength $p]!=1 || [lindex $p 0] ne "1"} {quit -f -code 1}
puts "BLACK_NATIVE_VERIFIED tb_perspective_coord"
quit -sim
vsim -voptargs=+acc work_black_b.tb_homography_solver
onfinish stop
run -all
set p [examine -value -radix binary -noshowbase sim:/tb_homography_solver/test_passed]
if {[llength $p]!=1 || [lindex $p 0] ne "1"} {quit -f -code 1}
puts "BLACK_NATIVE_VERIFIED tb_homography_solver"
quit -sim
vsim -voptargs=+acc work_black_b.tb_bilinear_interp
onfinish stop
run -all
set p [examine -value -radix binary -noshowbase sim:/tb_bilinear_interp/test_passed]
if {[llength $p]!=1 || [lindex $p 0] ne "1"} {quit -f -code 1}
puts "BLACK_NATIVE_VERIFIED tb_bilinear_interp"
quit -sim
vsim -voptargs=+acc work_black_b.tb_marker_detector
onfinish stop
run -all
set p [examine -value -radix binary -noshowbase sim:/tb_marker_detector/test_passed]
if {[llength $p]!=1 || [lindex $p 0] ne "1"} {quit -f -code 1}
puts "BLACK_NATIVE_VERIFIED tb_marker_detector"
quit -sim
vsim -voptargs=+acc work_black_b.tb_marker_config
onfinish stop
run -all
set p [examine -value -radix binary -noshowbase sim:/tb_marker_config/test_passed]
if {[llength $p]!=1 || [lindex $p 0] ne "1"} {quit -f -code 1}
puts "BLACK_NATIVE_VERIFIED tb_marker_config"
quit -sim
vsim -voptargs=+acc work_black_b.tb_b_rectifier
onfinish stop
run -all
set p [examine -value -radix binary -noshowbase sim:/tb_b_rectifier/test_passed]
if {[llength $p]!=1 || [lindex $p 0] ne "1"} {quit -f -code 1}
puts "BLACK_NATIVE_VERIFIED tb_b_rectifier"
quit -sim
vsim -voptargs=+acc work_black_b.tb_cache_contract
onfinish stop
run -all
set p [examine -value -radix binary -noshowbase sim:/tb_cache_contract/test_passed]
if {[llength $p]!=1 || [lindex $p 0] ne "1"} {quit -f -code 1}
puts "BLACK_NATIVE_VERIFIED tb_cache_contract"
quit -sim
vsim -voptargs=+acc work_black_b.tb_b_integration
onfinish stop
run -all
set p [examine -value -radix binary -noshowbase sim:/tb_b_integration/test_passed]
if {[llength $p]!=1 || [lindex $p 0] ne "1"} {quit -f -code 1}
puts "BLACK_NATIVE_VERIFIED tb_b_integration"
quit -sim
vsim -voptargs=+acc work_black_b.tb_request_boundaries
onfinish stop
run -all
set p [examine -value -radix binary -noshowbase sim:/tb_request_boundaries/test_passed]
if {[llength $p]!=1 || [lindex $p 0] ne "1"} {quit -f -code 1}
puts "BLACK_NATIVE_VERIFIED tb_request_boundaries"
quit -sim
puts "ALL_BLACK_NATIVE_CHECKS_PASS"
quit -f -code 0
