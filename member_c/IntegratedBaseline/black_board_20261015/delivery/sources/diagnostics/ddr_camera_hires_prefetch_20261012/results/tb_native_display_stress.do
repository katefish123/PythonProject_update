onerror {quit -f -code 1}
transcript file {D:/FPGA/output/c_black_burst_merge_v3_20261015/diagnostics/ddr_camera_hires_prefetch_20261012/results/tb_native_display_stress.transcript.log}
if {![file isdirectory work_tb_native_display_stress]} {vlib work_tb_native_display_stress}
vmap work_tb_native_display_stress work_tb_native_display_stress
vlog -sv -work work_tb_native_display_stress {D:/FPGA/output/c_black_burst_merge_v3_20261015/diagnostics/ddr_camera_hires_prefetch_20261012/results/ddr_result_display.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/vendor/c_current/01_design_code/video_timing_vtc.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/diagnostics/ddr_camera_hires_prefetch_20261012/tb_native_display.sv} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/algo/c_corner_rectifier.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/algo/capture_geometry.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/algo/geometry_frame_join.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/video/rx_preview.v} {D:/FPGA/output/c_black_burst_merge_v3_20261015/rtl/video/status_overlay.v}
vsim -c -voptargs=+acc -wlf {D:/FPGA/output/c_black_burst_merge_v3_20261015/diagnostics/ddr_camera_hires_prefetch_20261012/results/tb_native_display_stress.wlf} -gCONTENTIOUS=1 work_tb_native_display_stress.tb_native_display
onfinish stop
run -all
set pass_bit [examine -value -radix binary -noshowbase sim:/tb_native_display/test_passed]
if {[llength $pass_bit]!=1 || [lindex $pass_bit 0] ne "1"} {quit -f -code 1}
puts "VERIFIED_PASS_BIT=1"
quit -f -code 0
