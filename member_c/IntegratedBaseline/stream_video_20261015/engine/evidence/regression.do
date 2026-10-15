onerror {quit -f -code 1}
if {![file exists work_reg]} {vlib work_reg}
vlog -sv -work work_reg D:/FPGA/worktrees/c_pipeline_next/member_c/IntegratedBaseline/stream_video_20261015/engine/ddr_word_engine.v D:/FPGA/worktrees/c_pipeline_next/member_c/IntegratedBaseline/stream_video_20261015/engine/tb_ddr_word_engine.sv D:/FPGA/worktrees/c_pipeline_next/member_c/IntegratedBaseline/stream_video_20261015/engine/tb_ddr_read_ahead.sv D:/FPGA/worktrees/c_pipeline_next/member_c/IntegratedBaseline/stream_video_20261015/engine/tb_source_prefetch.sv D:/FPGA/worktrees/c_pipeline_next/member_c/IntegratedBaseline/stream_video_20261015/engine/tb_capture_burst_protocol.sv
foreach top {tb_ddr_word_engine tb_ddr_read_ahead tb_source_prefetch tb_capture_burst_protocol} {
 vsim -voptargs=+acc work_reg.$top
 onfinish stop
 run -all
 set pass_bit [examine -value -radix binary -noshowbase sim:/$top/test_passed]
 if {$pass_bit ne "1"} {quit -f -code 1}
 puts "VERIFIED_PASS $top"
 quit -sim
}
quit -f -code 0
