onerror {quit -f -code 1}
transcript file real_config.transcript.log
if {![file isdirectory work_real_config]} {vlib work_real_config}
vmap work_real_config work_real_config
vlog -sv -work work_real_config hdmi_config.v ms7200_ctl.v ms7210_ctl.v iic_dri.v tb_hdmi_config.sv
vsim -c -voptargs=+acc -wlf real_config.wlf -gTX_FIRST=1 work_real_config.tb_hdmi_config
onfinish stop
run -all
if {[examine -radix decimal sim:/tb_hdmi_config/test_failed] != 0} {quit -f -code 1}
quit -f -code 0
