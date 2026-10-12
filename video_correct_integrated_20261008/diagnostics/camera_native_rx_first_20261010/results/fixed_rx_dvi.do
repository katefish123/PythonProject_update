onerror {quit -f -code 1}
transcript file fixed_rx_dvi.transcript.log
if {![file isdirectory work_fixed_rx_dvi]} {vlib work_fixed_rx_dvi}
vmap work_fixed_rx_dvi work_fixed_rx_dvi
vlog -sv -work work_fixed_rx_dvi hdmi_config.v ms7200_ctl.v ms7210_ctl.v iic_dri.v ms72xx_i2c_test_device.sv tb_rx_reconnect.sv
vsim -c -voptargs=+acc -wlf fixed_rx_dvi.wlf -gTX_FIRST=0 -gINITIAL_STATUS=2 work_fixed_rx_dvi.tb_rx_reconnect
onfinish stop
run -all
if {[examine -radix decimal sim:/tb_rx_reconnect/test_failed] != 0} {quit -f -code 1}
quit -f -code 0
