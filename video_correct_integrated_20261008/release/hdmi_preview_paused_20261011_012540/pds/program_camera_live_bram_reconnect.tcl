# Temporary raw-camera preview in CRAM; no flash operation.
set root [file normalize [file join [file dirname [info script]] ..]]
set release [file join $root release camera_live_bram_reconnect_20261010]
set bit_file [file join $release camera_live_bram_top.sbit]
if {![file isfile $bit_file] || ![file isfile [file rootname $bit_file].smsk]} {error "Preview release bit/mask missing"}
set report_file [file join $release camera_live_bram_top_timing_summary_after_hold_fix.txt]
set report_handle [open $report_file r]
set report_text [read $report_handle]
close $report_handle
if {[string first "All Constraints Met" $report_text]<0} {error "Preview timing not qualified"}
cfg_set_tcl_break -flag true
cfg_connect -ip 127.0.0.1 -port 65420
cfg_set_cable_property -index 0 -freq 1MHz
cfg_scan_chain
cfg_assign_file -file $bit_file -device_index 0
cfg_set_device_property -device_index 0 -program 1 -readback 1
cfg_program -device_index 0
cfg_verify -device_index 0
cfg_read_device_property -device_index 0 -mode 3
cfg_disconnect
cfg_close
