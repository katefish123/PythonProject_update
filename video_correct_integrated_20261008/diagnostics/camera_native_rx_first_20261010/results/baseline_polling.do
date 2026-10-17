onerror {quit -f -code 1}
transcript file baseline_polling.transcript.log
if {![file isdirectory work_baseline_polling]} {vlib work_baseline_polling}
vmap work_baseline_polling work_baseline_polling
vlog -sv -work work_baseline_polling hdmi_config_baseline.v ms7200_ctl.v ms7210_ctl.v iic_dri.v ms72xx_i2c_test_device.sv tb_rx_reconnect.sv
vsim -c -voptargs=+acc -wlf baseline_polling.wlf -gTX_FIRST=0 -gINITIAL_STATUS=3 work_baseline_polling.tb_rx_reconnect
onfinish stop
run -all
if {[examine -radix decimal sim:/tb_rx_reconnect/test_failed] != 0} {quit -f -code 1}
quit -f -code 0
