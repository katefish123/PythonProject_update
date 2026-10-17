onerror {quit -f -code 1}
transcript file {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_coordqueue_20261013/results/tb_ddr_read_ahead.transcript.log}
if {![file isdirectory work_tb_ddr_read_ahead]} {vlib work_tb_ddr_read_ahead}
vmap work_tb_ddr_read_ahead work_tb_ddr_read_ahead
vlog -sv -work work_tb_ddr_read_ahead {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_hires_rowtrain_20261013/results/ddr_word_engine.v} {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_coordqueue_20261013/results/tb_ddr_read_ahead.sv}
vsim -c -voptargs=+acc -wlf {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_coordqueue_20261013/results/tb_ddr_read_ahead.wlf} work_tb_ddr_read_ahead.tb_ddr_read_ahead
onfinish stop
run -all
set pass_bit [examine -value -radix binary -noshowbase sim:/tb_ddr_read_ahead/test_passed]
if {[llength $pass_bit]!=1 || [lindex $pass_bit 0] ne "1"} {quit -f -code 1}
puts "VERIFIED_PASS_BIT=1"
quit -f -code 0
