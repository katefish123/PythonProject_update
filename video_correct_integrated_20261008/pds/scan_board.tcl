# Read-only JTAG identification before assigning/programming a bitstream.
cfg_set_tcl_break -flag true
cfg_connect -ip 127.0.0.1 -port 65420
cfg_set_cable_property -index 0 -freq 5MHz
cfg_scan_chain
cfg_read_device_property -device_index 0 -mode 0
cfg_read_device_property -device_index 0 -mode 3
cfg_disconnect
cfg_close
