onerror {quit -f -code 1}
transcript file config.log
if {![file isdirectory work_config]} {vlib work_config}
vmap work_config work_config
vlog -sv -work work_config ../../../rtl/hdmi/ms7200_ctl.v ../../../rtl/hdmi/ms7210_ctl.v ../../../rtl/hdmi/iic_dri.v hdmi_config_runtime_diag.v tb_runtime_config.sv
vsim -c -voptargs=+acc -wlf config.wlf -gTX_FIRST=1 work_config.tb_hdmi_config
run -all
if {[examine -radix decimal sim:/tb_hdmi_config/test_failed] != 0} {quit -f -code 1}
quit -f -code 0
