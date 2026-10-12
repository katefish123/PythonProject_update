# Read only. Uses the debugger's documented ADC register interface.
dbg_connect -ip 127.0.0.1 -port 65420
dbg_scan_chain
dbg_read_adc_register -address 0x18
dbg_disconnect
dbg_close
