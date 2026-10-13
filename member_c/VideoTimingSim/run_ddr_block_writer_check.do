onerror {quit -f -code 1}
onbreak {resume}
if {![file exists work_ddr_block_writer]} {vlib work_ddr_block_writer}
vmap work_ddr_block_writer work_ddr_block_writer
vlog -sv -work work_ddr_block_writer 01_design_code/ddr_block_writer.v 02_simulation/tb_ddr_block_writer.v
vsim -voptargs=+acc work_ddr_block_writer.tb_ddr_block_writer
onfinish stop
run -all
if {[examine -radix decimal /tb_ddr_block_writer/test_passed] != 1} {quit -f -code 1}
quit -sim
if {![info exists env(MEMBER_A_ENGINE)]} {error "Set MEMBER_A_ENGINE to the pinned A ddr_word_engine.v"}
vlog -sv -work work_ddr_block_writer $env(MEMBER_A_ENGINE) 01_design_code/rgb888_block_packer.v 01_design_code/ddr_memory_layout.v 01_design_code/ddr_capture_session.v 01_design_code/ddr_frame_slots.v 02_simulation/tb_ddr_writer_a_engine.v
vsim -voptargs=+acc work_ddr_block_writer.tb_ddr_writer_a_engine
onfinish stop
run -all
if {[examine -radix decimal /tb_ddr_writer_a_engine/test_passed] != 1} {quit -f -code 1}
quit -sim
vsim -voptargs=+acc -gUSE_SESSION=1 work_ddr_block_writer.tb_ddr_writer_a_engine
onfinish stop
run -all
if {[examine -radix decimal /tb_ddr_writer_a_engine/test_passed] != 1} {quit -f -code 1}
quit -f -code 0
