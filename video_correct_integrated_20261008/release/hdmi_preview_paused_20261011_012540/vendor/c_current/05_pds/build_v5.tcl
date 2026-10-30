# Run from 05_pds using pds_shell -file build_v5.tcl -project_name VideoTimingSim_V5
set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676
add_design "../01_design_code/video_timing_vtc.v"
add_design "../01_design_code/test_pattern_generator_tpg.v"
add_design "../01_design_code/video_top.v"
add_design "../01_design_code/third_party/ms7210/ms7210_ctl.v"
add_design "../01_design_code/third_party/ms7210/iic_dri.v"
add_design "../01_design_code/ms7210_config.v"
add_design "../01_design_code/ip/video_pll_27m_148m5/video_pll_27m_148m5.v"
add_design "../01_design_code/ip/config_pll_27m_10m/config_pll_27m_10m.v"
add_design "../01_design_code/hdmi_colorbar_top.v"
add_constraint -logic -fdc mes2l676_hdmi_out.fdc
compile -top_module hdmi_colorbar_top
synthesize -ads
dev_map
pnr
report_timing
gen_bit_stream
