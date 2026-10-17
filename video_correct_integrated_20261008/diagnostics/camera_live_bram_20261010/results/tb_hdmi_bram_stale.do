onerror {quit -f -code 1}
transcript file tb_hdmi_bram_stale.log
if {![file isdirectory work_tb_hdmi_bram_stale]} {vlib work_tb_hdmi_bram_stale}
vmap work_tb_hdmi_bram_stale work_tb_hdmi_bram_stale
vlog -sv -work work_tb_hdmi_bram_stale {hdmi_bram_probe.v} {tb_hdmi_bram_stale.v}
vsim -c -voptargs=+acc -wlf tb_hdmi_bram_stale.wlf work_tb_hdmi_bram_stale.tb_hdmi_bram_stale
run -all
if {[examine -radix decimal sim:/tb_hdmi_bram_stale/test_failed] != 0} {quit -f -code 1}
if {[examine -radix decimal sim:/tb_hdmi_bram_stale/test_passed] != 1} {quit -f -code 1}
quit -f -code 0
