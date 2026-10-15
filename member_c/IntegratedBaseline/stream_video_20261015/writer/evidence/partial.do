onerror {quit -code 1}
if {![file exists work]} {vlib work}
vlog -sv D:/FPGA/worktrees/c_pipeline_next/member_c/IntegratedBaseline/stream_video_20261015/writer/ddr_result_writer_stream.v D:/FPGA/worktrees/c_pipeline_next/member_c/IntegratedBaseline/stream_video_20261015/writer/tb_writer_partial.sv
vsim -voptargs=+acc work.tb_writer_partial
run -all
quit -code 0
