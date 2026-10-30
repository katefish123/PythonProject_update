onerror {quit -code 1}
transcript file 04_results/tpg_check.log

if {[file exists work_tpg_check]} {
    vdel -lib work_tpg_check -all
}
vlib work_tpg_check
vmap work_tpg_check work_tpg_check

vlog -work work_tpg_check 01_design_code/test_pattern_generator_tpg.v
vlog -work work_tpg_check 02_simulation/tb_tpg_patterns.v

vsim -c -wlf 04_results/tpg_check.wlf work_tpg_check.tb_tpg_patterns
run -all
quit -f
