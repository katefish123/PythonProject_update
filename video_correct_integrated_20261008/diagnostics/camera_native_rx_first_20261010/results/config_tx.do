onerror {quit -f -code 1}
transcript file config_tx.transcript.log
if {![file isdirectory work_config_tx]} {vlib work_config_tx}
vmap work_config_tx work_config_tx
vlog -sv -work work_config_tx hdmi_config.v ms7200_ctl.v ms7210_ctl.v iic_dri.v tb_hdmi_config.sv
vsim -c -voptargs=+acc -wlf config_tx.wlf -gTX_FIRST=1 work_config_tx.tb_hdmi_config
onfinish stop
run -all
if {[examine -radix decimal sim:/tb_hdmi_config/test_failed] != 0} {quit -f -code 1}
quit -f -code 0
