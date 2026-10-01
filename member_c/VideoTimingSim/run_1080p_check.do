onerror {quit -code 1}
transcript file 04_results/1080p_check.log

if {[file exists work_1080p]} {
    vdel -lib work_1080p -all
}
vlib work_1080p
vmap work_1080p work_1080p

vlog -work work_1080p 01_design_code/video_timing_vtc.v
vlog -work work_1080p 01_design_code/test_pattern_generator_tpg.v
vlog -work work_1080p 02_simulation/tb_video_timing_1080p.v

vsim -c -voptargs=+acc -wlf 04_results/1080p_check.wlf work_1080p.tb_video_timing_1080p
run -all
quit -f
