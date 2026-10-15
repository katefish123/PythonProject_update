onerror {quit -f -code 1}
transcript file {D:/FPGA/output/c_black_burst_merge_v3_20261015/diagnostics/ddr_camera_hires_prefetch_20261012/results/tb_ddr_read_ahead.transcript.log}
if {![file isdirectory work_tb_ddr_read_ahead]} {vlib work_tb_ddr_read_ahead}
vmap work_tb_ddr_read_ahead work_tb_ddr_read_ahead
vlog -sv -work work_tb_ddr_read_ahead {D:/FPGA/output/c_black_burst_merge_v3_20261015/diagnostics/ddr_camera_hires_prefetch_20261012/results/ddr_word_engine.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/diagnostics/ddr_camera_hires_prefetch_20261012/results/tb_ddr_read_ahead.sv} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/algo/c_corner_rectifier.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/algo/capture_geometry.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/algo/geometry_frame_join.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/video/rx_preview.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/video/status_overlay.v}
vsim -c -voptargs=+acc -wlf {D:/FPGA/output/c_black_burst_merge_v3_20261015/diagnostics/ddr_camera_hires_prefetch_20261012/results/tb_ddr_read_ahead.wlf} work_tb_ddr_read_ahead.tb_ddr_read_ahead
onfinish stop
run -all
set pass_bit [examine -value -radix binary -noshowbase sim:/tb_ddr_read_ahead/test_passed]
if {[llength $pass_bit]!=1 || [lindex $pass_bit 0] ne "1"} {quit -f -code 1}
puts "VERIFIED_PASS_BIT=1"
quit -f -code 0
