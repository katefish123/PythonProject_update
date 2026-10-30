# Reproducible PDS implementation flow for the current target.
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -top_module HDMI_IN_DDR3_ROI_top
synthesize -ads -selected_syn_tool_opt 2
dev_map
pnr
report_timing
report_power
gen_netlist
gen_bit_stream -master_configuration_clock_frequency {40M}
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -top_module HDMI_IN_DDR3_ROI_top
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -top_module HDMI_IN_DDR3_ROI_top
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -top_module HDMI_IN_DDR3_ROI_top
synthesize -dir {D:/PDS_2022.2/syn/bin/synplify_pro.exe} -ads -selected_syn_tool_opt 2 
dev_map 
pnr 
report_timing 
report_power 
gen_netlist 
gen_bit_stream -master_configuration_clock_frequency {40M} 
