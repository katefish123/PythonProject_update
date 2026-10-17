set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676
add_design {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/camera_bram_overlay_20261011/results/camera_live_bram_top.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/camera_bram_overlay_20261011/results/hdmi_bram_probe.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/camera_bram_overlay_20261011/results/cdc_snapshot.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/camera_bram_overlay_20261011/results/hdmi_config_runtime_diag.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/camera_bram_overlay_20261011/results/reset_sync.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/camera_bram_overlay_20261011/results/iic_dri.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/camera_bram_overlay_20261011/results/ms7200_ctl.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/camera_bram_overlay_20261011/results/ms7210_ctl.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/camera_bram_overlay_20261011/results/video_timing_vtc.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/camera_bram_overlay_20261011/results/video_pll_27m_148m5.v}
add_design {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/camera_bram_overlay_20261011/results/config_pll_27m_10m.v}
add_constraint -logic -fdc {C:/D/FPGA/video_correct_integrated_20261008/diagnostics/camera_bram_overlay_20261011/results/camera_live_bram.fdc}
compile -top_module camera_live_bram_top
synthesize -ads
dev_map
pnr
report_timing
gen_bit_stream
