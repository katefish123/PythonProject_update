onerror {quit -f -code 1}
transcript file pixels_missing_vs.transcript.log
if {![file isdirectory work_pixels_missing_vs]} {vlib work_pixels_missing_vs}
vmap work_pixels_missing_vs work_pixels_missing_vs
vlog -sv -work work_pixels_missing_vs camera_live_native_top.v reset_sync.v hdmi_vs_recover.v video_timing_vtc.v tb_native_pixels.sv
vsim -c -voptargs=+acc -wlf pixels_missing_vs.wlf -gMISSING_VS=1 -gH_FRONT=90 work_pixels_missing_vs.tb_hdmi_camera_native
onfinish stop
run -all
if {[examine -radix decimal sim:/tb_hdmi_camera_native/test_failed] != 0} {quit -f -code 1}
if {[examine -radix decimal sim:/tb_hdmi_camera_native/test_passed] != 1} {quit -f -code 1}
quit -f -code 0
