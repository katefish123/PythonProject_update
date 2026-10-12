onerror {quit -f -code 1}
transcript file pixels.log
if {[info exists env(RX_FIRST_MISSING_VS)]} {set missing_vs $env(RX_FIRST_MISSING_VS)} else {set missing_vs 0}
if {[info exists env(RX_FIRST_H_FRONT)]} {set h_front $env(RX_FIRST_H_FRONT)} else {set h_front 88}
if {![file isdirectory work_pixels]} {vlib work_pixels}
vmap work_pixels work_pixels
vlog -sv -work work_pixels hdmi_camera_passthrough_rx_first_top.v {C:/D/FPGA/video_correct_integrated_20261008/rtl/common/reset_sync.v} {C:/D/FPGA/video_correct_integrated_20261008/vendor/c_current/01_design_code/hdmi_vs_recover.v} {C:/D/FPGA/video_correct_integrated_20261008/vendor/c_current/01_design_code/video_timing_vtc.v} tb_rx_first_pixels.sv
vsim -c -voptargs=+acc -wlf pixels.wlf -gMISSING_VS=$missing_vs -gH_FRONT=$h_front work_pixels.tb_hdmi_camera_native
run -all
if {[examine -radix decimal sim:/tb_hdmi_camera_native/test_failed] != 0} {quit -f -code 1}
if {[examine -radix decimal sim:/tb_hdmi_camera_native/test_passed] != 1} {quit -f -code 1}
quit -f -code 0
