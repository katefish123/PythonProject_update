# Run from an empty output directory outside this repository.
set repo_root [file normalize [file join [file dirname [info script]] ..]]
if {![info exists ::env(MS7200_LOCAL_SOURCE)]} {error "Set MS7200_LOCAL_SOURCE to your externally prepared RX controller"}
set local_rx_source [file normalize $::env(MS7200_LOCAL_SOURCE)]
if {![file isfile $local_rx_source]} {error "External RX source does not exist"}
set checkout_root $repo_root
while {![file exists [file join $checkout_root .git]] && [file dirname $checkout_root] ne $checkout_root} {set checkout_root [file dirname $checkout_root]}
if {![file exists [file join $checkout_root .git]]} {set checkout_root $repo_root}
set root_prefix "[string tolower $checkout_root]/"
if {[string first $root_prefix "[string tolower $local_rx_source]/"] == 0} {error "Keep reference-derived RX code outside this repository"}
if {[string first $root_prefix "[string tolower [file normalize [pwd]]]/"] == 0} {error "Build from an output directory outside this repository"}
set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676
add_design $local_rx_source
foreach source {
 01_design_code/third_party/ms7210/ms7210_ctl.v
 01_design_code/third_party/ms7210/iic_dri.v
 01_design_code/ms72xx_shared_config.v
 01_design_code/ip/config_pll_27m_10m/config_pll_27m_10m.v
 01_design_code/hdmi_camera_loop_top.v
 01_design_code/hdmi_vs_recover.v
} {add_design [file join $repo_root $source]}
add_constraint -logic -fdc [file join $repo_root 05_pds/mes2l676_camera_native.fdc]
compile -top_module hdmi_camera_loop_top
synthesize -ads
dev_map
pnr
report_timing
gen_bit_stream
