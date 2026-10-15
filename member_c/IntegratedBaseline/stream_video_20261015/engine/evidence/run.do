onerror {quit -code 1}
if {![file exists work]} {vlib work}
vlog -sv D:/FPGA/worktrees/c_pipeline_next/member_c/IntegratedBaseline/stream_video_20261015/engine/ddr_word_engine.v D:/FPGA/worktrees/c_pipeline_next/member_c/IntegratedBaseline/stream_video_20261015/engine/tb_engine_block.sv
vsim -voptargs=+acc work.tb_engine_block
run -all
quit -code 0
