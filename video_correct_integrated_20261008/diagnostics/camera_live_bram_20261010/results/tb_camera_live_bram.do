onerror {quit -f -code 1}
transcript file tb_camera_live_bram.log
if {![file isdirectory work_tb_camera_live_bram]} {vlib work_tb_camera_live_bram}
vmap work_tb_camera_live_bram work_tb_camera_live_bram
vlog -sv -work work_tb_camera_live_bram {camera_live_bram_top.v} {hdmi_bram_probe.v} {cdc_snapshot.v} {C:/D/FPGA/video_correct_integrated_20261008/rtl/common/reset_sync.v} {C:/D/FPGA/video_correct_integrated_20261008/vendor/c_current/01_design_code/video_timing_vtc.v} {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/camera_live_bram_20261010/tb_camera_live_bram.v}
vsim -c -voptargs=+acc -wlf tb_camera_live_bram.wlf work_tb_camera_live_bram.tb_camera_live_bram
run -all
if {[examine -radix decimal sim:/tb_camera_live_bram/test_failed] != 0} {quit -f -code 1}
if {[examine -radix decimal sim:/tb_camera_live_bram/test_passed] != 1} {quit -f -code 1}
quit -f -code 0
