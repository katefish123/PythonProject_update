onerror {quit -f -code 1}
transcript file tb_hdmi_bram_probe.log
if {![file isdirectory work_tb_hdmi_bram_probe]} {vlib work_tb_hdmi_bram_probe}
vmap work_tb_hdmi_bram_probe work_tb_hdmi_bram_probe
vlog -sv -work work_tb_hdmi_bram_probe {hdmi_bram_probe.v} {tb_hdmi_bram_probe.v}
vsim -c -voptargs=+acc -wlf tb_hdmi_bram_probe.wlf work_tb_hdmi_bram_probe.tb_hdmi_bram_probe
run -all
if {[examine -radix decimal sim:/tb_hdmi_bram_probe/test_failed] != 0} {quit -f -code 1}
if {[examine -radix decimal sim:/tb_hdmi_bram_probe/test_passed] != 1} {quit -f -code 1}
quit -f -code 0
