onerror {quit -f -code 1}
transcript file reconnect_hdmi_tx_first.transcript.log
if {![file isdirectory work_reconnect_hdmi_tx_first]} {vlib work_reconnect_hdmi_tx_first}
vmap work_reconnect_hdmi_tx_first work_reconnect_hdmi_tx_first
vlog -sv -work work_reconnect_hdmi_tx_first hdmi_config.v ms7200_ctl.v ms7210_ctl.v iic_dri.v ms72xx_i2c_test_device.sv tb_rx_reconnect.sv
vsim -c -voptargs=+acc -wlf reconnect_hdmi_tx_first.wlf -gTX_FIRST=1 -gINITIAL_STATUS=3 work_reconnect_hdmi_tx_first.tb_rx_reconnect
onfinish stop
run -all
if {[examine -radix decimal sim:/tb_rx_reconnect/test_failed] != 0} {quit -f -code 1}
quit -f -code 0
