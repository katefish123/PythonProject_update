set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676
add_design {C:/D/FPGA/video_correct_integrated_20261008/rtl/top/hdmi_link_i2c_probe_v2_top.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/rtl/common/reset_sync.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/rtl/hdmi/diag/hdmi_config_diag_v2.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/rtl/hdmi/diag/iic_dri_diag_v2.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/rtl/hdmi/ms7200_ctl.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/rtl/hdmi/ms7210_ctl.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/vendor/c_current/01_design_code/video_timing_vtc.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/vendor/c_current/01_design_code/ip/video_pll_27m_148m5/video_pll_27m_148m5.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/vendor/c_current/01_design_code/ip/config_pll_27m_10m/config_pll_27m_10m.v}
add_constraint -logic -fdc {C:/D/FPGA/video_correct_integrated_20261008/results/hdmi_link_i2c_probe_v2/hdmi_link_i2c_probe_v2.fdc}
compile -top_module hdmi_link_i2c_probe_v2_top
synthesize -ads
dev_map
pnr
report_timing
gen_bit_stream
