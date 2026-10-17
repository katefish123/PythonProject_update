onerror {quit -code 1}
transcript file 04_results/hdmi_real_compile.log
# Point PDS_SIM_GPLL to GTP_GPLL.v when PDS is installed elsewhere.
if {[info exists env(PDS_SIM_GPLL)]} {
    set gpll_model $env(PDS_SIM_GPLL)
} else {
    set gpll_model "D:/softwares/PDS/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation/GTP_GPLL.v"
}
if {![file exists $gpll_model]} {error "Set PDS_SIM_GPLL to the installed PDS GTP_GPLL.v"}
if {[file exists work_hdmi_real]} {vdel -lib work_hdmi_real -all}
vlib work_hdmi_real
vmap work_hdmi_real work_hdmi_real
vlog -work work_hdmi_real $gpll_model
vlog -work work_hdmi_real -f hardware_sources.f
vsim -c -voptargs=+acc -wlf 04_results/hdmi_real_compile.wlf work_hdmi_real.hdmi_colorbar_top
echo "TEST_PASS_HDMI_REAL_COMPILE (compile and elaboration only)"
quit -f
