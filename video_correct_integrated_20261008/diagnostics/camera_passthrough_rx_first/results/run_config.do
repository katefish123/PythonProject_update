onerror {quit -f -code 1}
transcript file rx_first_config.log
if {![file isdirectory work_rx_config]} {vlib work_rx_config}
vmap work_rx_config work_rx_config
vlog -sv -work work_rx_config {C:/D/FPGA/video_correct_integrated_20261008/rtl/hdmi/ms7200_ctl.v} {C:/D/FPGA/video_correct_integrated_20261008/rtl/hdmi/ms7210_ctl.v} {C:/D/FPGA/video_correct_integrated_20261008/rtl/hdmi/iic_dri.v} {C:/D/FPGA/video_correct_integrated_20261008/rtl/hdmi/hdmi_config.v} {C:/D/FPGA/video_correct_integrated_20261008/sim/tb_hdmi_config.sv}
vsim -c -voptargs=+acc -wlf rx_first_config.wlf -gTX_FIRST=0 work_rx_config.tb_hdmi_config
run -all
if {[examine -radix decimal sim:/tb_hdmi_config/test_failed] != 0} {quit -f -code 1}
quit -f -code 0
