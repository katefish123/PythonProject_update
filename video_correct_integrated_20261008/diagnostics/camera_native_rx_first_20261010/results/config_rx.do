onerror {quit -f -code 1}
transcript file config_rx.transcript.log
if {![file isdirectory work_config_rx]} {vlib work_config_rx}
vmap work_config_rx work_config_rx
vlog -sv -work work_config_rx hdmi_config.v ms7200_ctl.v ms7210_ctl.v iic_dri.v tb_hdmi_config.sv
vsim -c -voptargs=+acc -wlf config_rx.wlf -gTX_FIRST=0 work_config_rx.tb_hdmi_config
onfinish stop
run -all
if {[examine -radix decimal sim:/tb_hdmi_config/test_failed] != 0} {quit -f -code 1}
quit -f -code 0
