set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676
add_design {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/camera_native_rx_first_20261010/results/camera_native_rx_first_top.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/camera_native_rx_first_20261010/results/reset_sync.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/camera_native_rx_first_20261010/results/hdmi_config.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/camera_native_rx_first_20261010/results/ms7200_ctl.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/camera_native_rx_first_20261010/results/ms7210_ctl.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/camera_native_rx_first_20261010/results/iic_dri.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/camera_native_rx_first_20261010/results/hdmi_vs_recover.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/camera_native_rx_first_20261010/results/config_pll_27m_10m.v}
add_constraint -logic -fdc {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/camera_native_rx_first_20261010/results/camera_native_rx_first.fdc}
compile -top_module camera_native_rx_first_top
synthesize -ads
dev_map
pnr
report_timing
gen_bit_stream
