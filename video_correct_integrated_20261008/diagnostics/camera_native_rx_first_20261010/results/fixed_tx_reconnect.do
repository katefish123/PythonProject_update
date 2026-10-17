onerror {quit -f -code 1}
transcript file fixed_tx_reconnect.transcript.log
if {![file isdirectory work_fixed_tx_reconnect]} {vlib work_fixed_tx_reconnect}
vmap work_fixed_tx_reconnect work_fixed_tx_reconnect
vlog -sv -work work_fixed_tx_reconnect hdmi_config.v ms7200_ctl.v ms7210_ctl.v iic_dri.v ms72xx_i2c_test_device.sv tb_rx_reconnect.sv
vsim -c -voptargs=+acc -wlf fixed_tx_reconnect.wlf -gTX_FIRST=1 -gINITIAL_STATUS=3 work_fixed_tx_reconnect.tb_rx_reconnect
onfinish stop
run -all
if {[examine -radix decimal sim:/tb_rx_reconnect/test_failed] != 0} {quit -f -code 1}
quit -f -code 0
