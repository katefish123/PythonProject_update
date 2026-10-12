onerror {quit -f -code 1}
if {[info exists env(TX_FIRST)]} {set tx_first $env(TX_FIRST)} else {set tx_first 1}
transcript file results/hdmi_config_$tx_first.log
if {[file exists work_hdmi_config]} {vdel -lib work_hdmi_config -all}
vlib work_hdmi_config
vmap work_hdmi_config work_hdmi_config
vlog -work work_hdmi_config rtl/hdmi/ms7200_ctl.v rtl/hdmi/ms7210_ctl.v rtl/hdmi/iic_dri.v rtl/hdmi/hdmi_config.v sim/tb_hdmi_config.sv
vsim -c -voptargs=+acc -wlf results/hdmi_config.wlf -gTX_FIRST=$tx_first work_hdmi_config.tb_hdmi_config
run -all
if {[examine -radix decimal sim:/tb_hdmi_config/test_failed] != 0} {quit -f -code 1}
quit -f -code 0

