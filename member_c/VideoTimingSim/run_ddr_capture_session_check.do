onerror {quit -f -code 1}
onbreak {resume}
if {![file exists work_ddr_capture_session]} {vlib work_ddr_capture_session}
vmap work_ddr_capture_session work_ddr_capture_session
vlog -sv -work work_ddr_capture_session 01_design_code/ddr_memory_layout.v 01_design_code/ddr_capture_session.v 01_design_code/ddr_frame_slots.v 01_design_code/ddr_block_writer.v 02_simulation/tb_ddr_capture_session.v
vsim -voptargs=+acc work_ddr_capture_session.tb_ddr_capture_session
onfinish stop
run -all
if {[examine -radix decimal /tb_ddr_capture_session/test_passed] != 1} {quit -f -code 1}
quit -f -code 0
