transcript on
cd sim
if {[file exists work_ddr_display]} {vdel -lib work_ddr_display -all}
vlib work_ddr_display
vmap work_ddr_display work_ddr_display
vlog -sv -work work_ddr_display ../vendor/c_current/01_design_code/video_timing_vtc.v ../rtl/video/ddr_result_display.v tb_ddr_display.sv
vsim -c -lib work_ddr_display tb_ddr_display
run -all
quit -f
