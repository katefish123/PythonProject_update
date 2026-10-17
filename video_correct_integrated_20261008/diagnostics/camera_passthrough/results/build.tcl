set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676
add_design {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/camera_passthrough/hdmi_camera_passthrough_top.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/rtl/common/reset_sync.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/rtl/hdmi/hdmi_config.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/rtl/hdmi/iic_dri.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/rtl/hdmi/ms7200_ctl.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/rtl/hdmi/ms7210_ctl.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/vendor/c_current/01_design_code/hdmi_vs_recover.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/vendor/c_current/01_design_code/ip/config_pll_27m_10m/config_pll_27m_10m.v}
add_constraint -logic -fdc {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/camera_passthrough/results/camera_passthrough.fdc}
compile -top_module hdmi_camera_passthrough_top
synthesize -ads
dev_map
pnr
report_timing
gen_bit_stream
