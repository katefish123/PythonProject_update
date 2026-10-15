onerror {quit -f -code 1}
if {![file isdirectory work_banked_fullhd]} {vlib work_banked_fullhd}
vmap work_banked_fullhd work_banked_fullhd
vlog -sv -work work_banked_fullhd {D:/FPGA/output/c_black_burst_merge_v3_20261015/diagnostics/ddr_camera_hires_prefetch_20261012/results/ddr_word_engine.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/diagnostics/ddr_camera_hires_prefetch_20261012/results/ddr_result_display.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/memory/ddr_arbiter3.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/video/ddr_snapshot_capture.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/memory/async_packet_fifo.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/memory/ddr_capture_writer.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/vendor/c_current/01_design_code/video_timing_vtc.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/fullhd_tests/tb_banked_capture_display.sv} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/algo/c_corner_rectifier.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/algo/capture_geometry.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/algo/geometry_frame_join.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/video/rx_preview.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/video/status_overlay.v}
vsim -c -voptargs=+acc work_banked_fullhd.tb_banked_capture_display
onfinish stop
run -all
if {[examine -value -radix binary sim:/tb_banked_capture_display/test_passed] ne "1"} {quit -f -code 1}
puts "VERIFIED_PASS_BIT=1"
quit -f -code 0
