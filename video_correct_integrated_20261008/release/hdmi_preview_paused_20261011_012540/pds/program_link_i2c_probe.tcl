# Temporary first-NACK diagnostic image; CRAM only.
set root [file normalize [file join [file dirname [info script]] ..]]
set bit_file [file join $root results hdmi_link_i2c_probe generate_bitstream hdmi_link_i2c_probe_top.sbit]
if {![file isfile $bit_file] || ![file isfile [file rootname $bit_file].smsk]} {
    error "Probe bitstream and matching mask are required"
}
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
