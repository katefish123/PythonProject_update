transcript on

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

vlog -work work 01_design_code/video_timing_vtc.v
vlog -work work 01_design_code/test_pattern_generator_tpg.v
vlog -work work 02_simulation/tb_video_timing.v
vsim -voptargs=+acc work.tb_video_timing
onfinish stop

add wave -divider {Clock and Reset}
add wave sim:/tb_video_timing/clk
add wave sim:/tb_video_timing/rst_n

add wave -divider {Video Position}
add wave -radix unsigned sim:/tb_video_timing/h_cnt
add wave -radix unsigned sim:/tb_video_timing/v_cnt

add wave -divider {Video Control}
add wave sim:/tb_video_timing/hsync
add wave sim:/tb_video_timing/vsync
add wave sim:/tb_video_timing/de

add wave -divider {Pixel Color}
add wave -radix hexadecimal sim:/tb_video_timing/rgb

run -all
wave zoom full
