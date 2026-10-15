onerror {quit -f -code 1}
transcript file {D:/FPGA/output/c_black_burst_merge_v3_20261015/diagnostics/ddr_camera_hires_prefetch_20261012/results/tb_ddr_word_engine.transcript.log}
if {![file isdirectory work_tb_ddr_word_engine]} {vlib work_tb_ddr_word_engine}
vmap work_tb_ddr_word_engine work_tb_ddr_word_engine
vlog -sv -work work_tb_ddr_word_engine {D:/FPGA/output/c_black_burst_merge_v3_20261015/diagnostics/ddr_camera_hires_prefetch_20261012/results/ddr_word_engine.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/diagnostics/ddr_camera_hires_prefetch_20261012/results/tb_ddr_word_engine.sv} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/algo/c_corner_rectifier.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/algo/capture_geometry.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/algo/geometry_frame_join.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/video/rx_preview.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/video/status_overlay.v}
vsim -c -voptargs=+acc -wlf {D:/FPGA/output/c_black_burst_merge_v3_20261015/diagnostics/ddr_camera_hires_prefetch_20261012/results/tb_ddr_word_engine.wlf} work_tb_ddr_word_engine.tb_ddr_word_engine
onfinish stop
run -all
set pass_bit [examine -value -radix binary -noshowbase sim:/tb_ddr_word_engine/test_passed]
if {[llength $pass_bit]!=1 || [lindex $pass_bit 0] ne "1"} {quit -f -code 1}
puts "VERIFIED_PASS_BIT=1"
quit -f -code 0
