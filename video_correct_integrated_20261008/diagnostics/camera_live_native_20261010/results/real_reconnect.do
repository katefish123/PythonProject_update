onerror {quit -f -code 1}
transcript file real_reconnect.transcript.log
if {![file isdirectory work_real_reconnect]} {vlib work_real_reconnect}
vmap work_real_reconnect work_real_reconnect
vlog -sv -work work_real_reconnect hdmi_config.v ms7200_ctl.v ms7210_ctl.v iic_dri.v ms72xx_i2c_test_device.sv tb_rx_reconnect.sv
vsim -c -voptargs=+acc -wlf real_reconnect.wlf -gINITIAL_STATUS=3 work_real_reconnect.tb_rx_reconnect
onfinish stop
run -all
if {[examine -radix decimal sim:/tb_rx_reconnect/test_failed] != 0} {quit -f -code 1}
if {[examine -radix decimal sim:/tb_rx_reconnect/test_passed] != 1} {quit -f -code 1}
quit -f -code 0
