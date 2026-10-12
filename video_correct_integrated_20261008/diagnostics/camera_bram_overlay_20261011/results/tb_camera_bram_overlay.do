onerror {quit -f -code 1}
transcript file tb_camera_bram_overlay.transcript.log
if {![file isdirectory work_tb_camera_bram_overlay]} {vlib work_tb_camera_bram_overlay}
vmap work_tb_camera_bram_overlay work_tb_camera_bram_overlay
vlog -sv -work work_tb_camera_bram_overlay camera_live_bram_top.v hdmi_bram_probe.v cdc_snapshot.v reset_sync.v video_timing_vtc.v tb_camera_bram_overlay.v
vsim -c -voptargs=+acc -wlf tb_camera_bram_overlay.wlf work_tb_camera_bram_overlay.tb_camera_bram_overlay
onfinish stop
run -all
if {[examine -radix decimal sim:/tb_camera_bram_overlay/test_failed] != 0} {quit -f -code 1}
if {[examine -radix decimal sim:/tb_camera_bram_overlay/test_passed] != 1} {quit -f -code 1}
quit -f -code 0
