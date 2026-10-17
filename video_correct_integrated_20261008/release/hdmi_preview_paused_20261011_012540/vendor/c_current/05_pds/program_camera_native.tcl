# Explicitly invoked local CRAM programming; do not program Flash/eFuse.
if {![info exists ::env(CAMERA_SBIT)]} {error "Set CAMERA_SBIT to the reviewed local camera bitstream"}
set camera_sbit [file normalize $::env(CAMERA_SBIT)]
if {![file isfile $camera_sbit] || ![file isfile [file rootname $camera_sbit].smsk]} {error "Both .sbit and matching .smsk are required"}
cfg_set_tcl_break -flag true
cfg_connect -ip 127.0.0.1 -port 65420
cfg_scan_chain
cfg_assign_file -file $camera_sbit -device_index 0
cfg_set_device_property -device_index 0 -program 1
cfg_program -device_index 0
cfg_verify -device_index 0
cfg_disconnect
cfg_close
