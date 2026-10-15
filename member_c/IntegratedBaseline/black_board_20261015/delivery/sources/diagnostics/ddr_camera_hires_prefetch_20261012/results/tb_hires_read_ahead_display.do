onerror {quit -f -code 1}
transcript file {D:/FPGA/output/c_black_burst_merge_v3_20261015/diagnostics/ddr_camera_hires_prefetch_20261012/results/tb_hires_read_ahead_display.transcript.log}
if {![file isdirectory work_tb_hires_read_ahead_display]} {vlib work_tb_hires_read_ahead_display}
vmap work_tb_hires_read_ahead_display work_tb_hires_read_ahead_display
vlog -sv -work work_tb_hires_read_ahead_display {D:/FPGA/output/c_black_burst_merge_v3_20261015/diagnostics/ddr_camera_hires_prefetch_20261012/results/ddr_word_engine.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/diagnostics/ddr_camera_hires_prefetch_20261012/results/ddr_result_display.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/memory/ddr_arbiter3.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/vendor/c_current/01_design_code/video_timing_vtc.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/diagnostics/ddr_camera_hires_prefetch_20261012/results/tb_hires_read_ahead_display.sv} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/algo/c_corner_rectifier.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/algo/capture_geometry.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/algo/geometry_frame_join.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/video/rx_preview.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/video/status_overlay.v}
vsim -c -voptargs=+acc -wlf {D:/FPGA/output/c_black_burst_merge_v3_20261015/diagnostics/ddr_camera_hires_prefetch_20261012/results/tb_hires_read_ahead_display.wlf} work_tb_hires_read_ahead_display.tb_hires_read_ahead_display
onfinish stop
run -all
set pass_bit [examine -value -radix binary -noshowbase sim:/tb_hires_read_ahead_display/test_passed]
if {[llength $pass_bit]!=1 || [lindex $pass_bit 0] ne "1"} {quit -f -code 1}
puts "VERIFIED_PASS_BIT=1"
quit -f -code 0
