onerror {quit -f -code 1}
transcript file snapshot.log
if {![file isdirectory work_snapshot]} {vlib work_snapshot}
vmap work_snapshot work_snapshot
vlog -sv -work work_snapshot ../hdmi_runtime_probe_top.v ../../../rtl/common/reset_sync.v ../tb_runtime_snapshot.sv
vsim -c -voptargs=+acc -wlf snapshot.wlf work_snapshot.tb_runtime_snapshot
run -all
if {[examine -radix decimal sim:/tb_runtime_snapshot/test_failed] != 0} {quit -f -code 1}
quit -f -code 0
