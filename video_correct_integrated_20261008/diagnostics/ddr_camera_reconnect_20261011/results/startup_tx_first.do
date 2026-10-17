onerror {quit -f -code 1}
transcript file startup_tx_first.transcript.log
if {![file isdirectory work_startup_tx_first]} {vlib work_startup_tx_first}
vmap work_startup_tx_first work_startup_tx_first
vlog -sv -work work_startup_tx_first hdmi_config.v ms7200_ctl.v ms7210_ctl.v iic_dri.v tb_hdmi_config.sv
vsim -c -voptargs=+acc -wlf startup_tx_first.wlf -gTX_FIRST=1 work_startup_tx_first.tb_hdmi_config
onfinish stop
run -all
if {[examine -radix decimal sim:/tb_hdmi_config/test_failed] != 0} {quit -f -code 1}
quit -f -code 0
