onerror {quit -f -code 1}
transcript file baseline.transcript.log
if {![file isdirectory work_baseline]} {vlib work_baseline}
vmap work_baseline work_baseline
vlog -sv -work work_baseline {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/receiver_reconnect_20261010/results/ms7200_ctl_baseline.v} {C:/D/FPGA/video_correct_integrated_20261008/rtl/hdmi/ms7210_ctl.v} {C:/D/FPGA/video_correct_integrated_20261008/rtl/hdmi/iic_dri.v} {C:/D/FPGA/video_correct_integrated_20261008/rtl/hdmi/hdmi_config.v} {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/receiver_reconnect_20261010/results/ms72xx_i2c_test_device.sv} {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/receiver_reconnect_20261010/tb_rx_reconnect.sv}
vsim -c -voptargs=+acc -wlf baseline.wlf  work_baseline.tb_rx_reconnect
onfinish stop
run -all
if {[examine -radix decimal sim:/tb_rx_reconnect/test_failed] != 0} {quit -f -code 1}
quit -f -code 0
