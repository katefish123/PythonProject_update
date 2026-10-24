cfg_set_tcl_break -flag true
cfg_connect -ip 127.0.0.1 -port 65420
cfg_scan_chain
cfg_assign_file -file {D:/FPGA/deliveries/FullHD_LiveRepair_20261024/release/video_correct_ddr_top.sbit} -device_index 0
cfg_set_device_property -device_index 0 -program 1
cfg_program -device_index 0
cfg_verify -device_index 0
cfg_disconnect
cfg_close
