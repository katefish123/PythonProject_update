onerror {quit -f -code 1}
onbreak {resume}
if {![info exists ::env(MS7200_LOCAL_SOURCE)] || ![file isfile $::env(MS7200_LOCAL_SOURCE)]} {error "Set MS7200_LOCAL_SOURCE to an external prepared RX controller"}
if {![file exists work_camera_i2c]} {vlib work_camera_i2c}
vmap work_camera_i2c work_camera_i2c
vlog -work work_camera_i2c $::env(MS7200_LOCAL_SOURCE) 01_design_code/third_party/ms7210/ms7210_ctl.v 01_design_code/third_party/ms7210/iic_dri.v 01_design_code/ms72xx_shared_config.v 02_simulation/tb_ms72xx_shared_config.v
vsim -voptargs=+acc -t 1ns -gTX_FIRST=0 -gINITIAL_LOCKED=1 work_camera_i2c.tb_ms72xx_shared_config
onfinish stop
run -all
if {[examine -radix decimal /tb_ms72xx_shared_config/test_failed] != 0 || [examine -radix decimal /tb_ms72xx_shared_config/test_passed] != 1} {quit -f -code 1}
quit -f -code 0
