# Temporary HDMI input/status probe. CRAM only; no Flash or eFuse operations.
set root [file normalize [file join [file dirname [info script]] ..]]
set bit_file [file join $root diagnostics hdmi_runtime results generate_bitstream hdmi_runtime_probe_top.sbit]
if {![file isfile $bit_file] || ![file isfile [file rootname $bit_file].smsk]} {error "Bitstream/mask missing"}
cfg_set_tcl_break -flag true
cfg_connect -ip 127.0.0.1 -port 65420
cfg_set_cable_property -index 0 -freq 5MHz
cfg_scan_chain
cfg_assign_file -file $bit_file -device_index 0
cfg_set_device_property -device_index 0 -program 1
cfg_program -device_index 0
cfg_verify -device_index 0
cfg_read_device_property -device_index 0 -mode 3
cfg_disconnect
cfg_close
