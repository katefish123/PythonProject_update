onerror {quit -code 1}
transcript file 04_results/hdmi_board_check.log

if {[file exists work_hdmi_board_check]} {
    vdel -lib work_hdmi_board_check -all
}
vlib work_hdmi_board_check
vmap work_hdmi_board_check work_hdmi_board_check

vlog -work work_hdmi_board_check 01_design_code/video_timing_vtc.v
vlog -work work_hdmi_board_check 01_design_code/test_pattern_generator_tpg.v
vlog -work work_hdmi_board_check 01_design_code/video_top.v
vlog -work work_hdmi_board_check 01_design_code/ms7210_config.v
vlog -work work_hdmi_board_check 01_design_code/hdmi_colorbar_top.v
vlog -work work_hdmi_board_check 02_simulation/tb_hdmi_colorbar_top.v

vsim -c -voptargs=+acc -wlf 04_results/hdmi_board_check.wlf work_hdmi_board_check.tb_hdmi_colorbar_top
run -all

set test_failed [examine -radix decimal sim:/tb_hdmi_colorbar_top/test_failed]
if {$test_failed != 0} {
    quit -code 1
}
quit -f

