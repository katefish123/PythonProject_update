onerror {quit -f -code 1}
onbreak {resume}
if {![info exists env(MEMBER_B_RTL)]} {error "Set MEMBER_B_RTL to member B final/rtl directory"}
if {![file exists work_source_marker]} {vlib work_source_marker}
vmap work_source_marker work_source_marker
vlog -sv -work work_source_marker 01_design_code/hdmi_source_stream.v 02_simulation/tb_source_stream_marker.v
foreach name {unsigned_div_seq.v marker_detector.v} {
 vlog -work work_source_marker [file join $env(MEMBER_B_RTL) $name]
}
vsim -voptargs=+acc work_source_marker.tb_source_stream_marker
onfinish stop
run -all
if {[examine -radix decimal /tb_source_stream_marker/test_passed] != 1} {quit -f -code 1}
quit -f -code 0
