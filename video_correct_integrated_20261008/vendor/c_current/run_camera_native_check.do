onerror {quit -f -code 1}
onbreak {resume}
if {![file exists work_camera_native]} {vlib work_camera_native}
vmap work_camera_native work_camera_native
vlog -sv -work work_camera_native 01_design_code/video_timing_vtc.v 01_design_code/hdmi_vs_recover.v 01_design_code/hdmi_camera_loop_top.v 02_simulation/tb_hdmi_camera_native.v
vsim -voptargs=+acc -t 1ps work_camera_native.tb_hdmi_camera_native
onfinish stop
run -all
if {[examine -radix decimal /tb_hdmi_camera_native/test_failed] != 0 || [examine -radix decimal /tb_hdmi_camera_native/test_passed] != 1} {quit -f -code 1}
quit -f -code 0
