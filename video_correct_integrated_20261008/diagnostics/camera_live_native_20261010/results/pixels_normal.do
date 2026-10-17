onerror {quit -f -code 1}
transcript file pixels_normal.transcript.log
if {![file isdirectory work_pixels_normal]} {vlib work_pixels_normal}
vmap work_pixels_normal work_pixels_normal
vlog -sv -work work_pixels_normal camera_live_native_top.v reset_sync.v hdmi_vs_recover.v video_timing_vtc.v tb_native_pixels.sv
vsim -c -voptargs=+acc -wlf pixels_normal.wlf -gMISSING_VS=0 -gH_FRONT=88 work_pixels_normal.tb_hdmi_camera_native
onfinish stop
run -all
if {[examine -radix decimal sim:/tb_hdmi_camera_native/test_failed] != 0} {quit -f -code 1}
if {[examine -radix decimal sim:/tb_hdmi_camera_native/test_passed] != 1} {quit -f -code 1}
quit -f -code 0
