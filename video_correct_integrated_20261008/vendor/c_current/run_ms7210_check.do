onerror {quit -code 1}
transcript file 04_results/ms7210_config_check.log
if {[file exists work_ms7210_check]} {vdel -lib work_ms7210_check -all}
vlib work_ms7210_check
vmap work_ms7210_check work_ms7210_check
vlog -work work_ms7210_check 01_design_code/third_party/ms7210/ms7210_ctl.v
vlog -work work_ms7210_check 01_design_code/third_party/ms7210/iic_dri.v
vlog -work work_ms7210_check 01_design_code/ms7210_config.v
vlog -work work_ms7210_check 02_simulation/tb_ms7210_config.v
vsim -c -voptargs=+acc -wlf 04_results/ms7210_config_check.wlf work_ms7210_check.tb_ms7210_config
onfinish stop
run -all
set test_failed [examine -radix decimal sim:/tb_ms7210_config/test_failed]
set test_passed [examine -radix decimal sim:/tb_ms7210_config/test_passed]
if {$test_failed != 0 || $test_passed != 1} {quit -code 1}
quit -f
