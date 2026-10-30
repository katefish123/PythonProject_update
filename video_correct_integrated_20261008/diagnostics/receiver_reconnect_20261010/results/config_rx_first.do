onerror {quit -f -code 1}
transcript file config_rx_first.transcript.log
if {![file isdirectory work_config_rx_first]} {vlib work_config_rx_first}
vmap work_config_rx_first work_config_rx_first
vlog -sv -work work_config_rx_first {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/receiver_reconnect_20261010/results/ms7200_ctl_reconnect.v} {C:/D/FPGA/video_correct_integrated_20261008/rtl/hdmi/ms7210_ctl.v} {C:/D/FPGA/video_correct_integrated_20261008/rtl/hdmi/iic_dri.v} {C:/D/FPGA/video_correct_integrated_20261008/rtl/hdmi/hdmi_config.v} {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/receiver_reconnect_20261010/results/tb_hdmi_config_regression.sv}
vsim -c -voptargs=+acc -wlf config_rx_first.wlf -gTX_FIRST=0 work_config_rx_first.tb_hdmi_config
onfinish stop
run -all
if {[examine -radix decimal sim:/tb_hdmi_config/test_failed] != 0} {quit -f -code 1}
quit -f -code 0
