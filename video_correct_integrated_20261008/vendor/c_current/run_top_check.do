onerror {quit -code 1}
transcript file 04_results/top_check.log

if {[file exists work_top_check]} {
    vdel -lib work_top_check -all
}
vlib work_top_check
vmap work_top_check work_top_check

vlog -work work_top_check 01_design_code/video_timing_vtc.v
vlog -work work_top_check 01_design_code/test_pattern_generator_tpg.v
vlog -work work_top_check 01_design_code/video_top.v
vlog -work work_top_check 02_simulation/tb_video_top.v

vsim -c -voptargs=+acc -wlf 04_results/top_check.wlf work_top_check.tb_video_top
run -all

set test_failed [examine -radix decimal sim:/tb_video_top/test_failed]
if {$test_failed != 0} {
    quit -code 1
}
quit -f
