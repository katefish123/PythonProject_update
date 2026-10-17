onerror {quit -f -code 1}
onbreak {resume}
if {![file exists work_ddr_application]} {vlib work_ddr_application}
vmap work_ddr_application work_ddr_application
vlog -sv -work work_ddr_application 01_design_code/rgb888_block_packer.v 01_design_code/ddr_frame_slots.v 02_simulation/tb_ddr_application.v 02_simulation/tb_ddr_frame_model.v
vsim -voptargs=+acc work_ddr_application.tb_ddr_application
onfinish stop
run -all
if {[examine -radix decimal /tb_ddr_application/test_passed] != 1} {quit -f -code 1}
quit -sim
vsim -voptargs=+acc work_ddr_application.tb_ddr_frame_model
onfinish stop
run -all
if {[examine -radix decimal /tb_ddr_frame_model/test_passed] != 1} {quit -f -code 1}
quit -f -code 0
