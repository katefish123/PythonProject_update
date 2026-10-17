onerror {quit -f -code 1}
transcript file pixels.transcript.log
if {![file isdirectory work_pixels]} {vlib work_pixels}
vmap work_pixels work_pixels
vlog -sv -work work_pixels camera_native_rx_first_top.v reset_sync.v hdmi_vs_recover.v video_timing_vtc.v tb_native_pixels.sv
vsim -c -voptargs=+acc -wlf pixels.wlf -gMISSING_VS=0 -gH_FRONT=88 work_pixels.tb_hdmi_camera_native
onfinish stop
run -all
if {[examine -radix decimal sim:/tb_hdmi_camera_native/test_failed] != 0} {quit -f -code 1}
quit -f -code 0
