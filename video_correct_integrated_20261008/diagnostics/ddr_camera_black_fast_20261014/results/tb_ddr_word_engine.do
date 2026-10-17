onerror {quit -f -code 1}
transcript file {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_fast_20261014/results/tb_ddr_word_engine.transcript.log}
if {![file isdirectory work_tb_ddr_word_engine]} {vlib work_tb_ddr_word_engine}
vmap work_tb_ddr_word_engine work_tb_ddr_word_engine
vlog -sv -work work_tb_ddr_word_engine {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_fast_20261014/src/diagnostics/ddr_camera_hires_rowtrain_20261013/results/ddr_word_engine.v} {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_fast_20261014/results/tb_ddr_word_engine.sv}
vsim -c -voptargs=+acc -wlf {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/ddr_camera_black_fast_20261014/results/tb_ddr_word_engine.wlf} work_tb_ddr_word_engine.tb_ddr_word_engine
onfinish stop
run -all
set pass_bit [examine -value -radix binary -noshowbase sim:/tb_ddr_word_engine/test_passed]
if {[llength $pass_bit]!=1 || [lindex $pass_bit 0] ne "1"} {quit -f -code 1}
puts "VERIFIED_PASS_BIT=1"
quit -f -code 0
