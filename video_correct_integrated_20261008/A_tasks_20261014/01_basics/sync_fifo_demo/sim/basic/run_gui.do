# Run from the ModelSim Transcript. Keep the GUI and waveform open.
# ModelSim's do macro does not reliably expose its filename via info script.
set here C:/D/FPGA/demo/Projects/sync_fifo_demo/sim/basic
quit -sim
cd $here
if {![file exists work]} {vlib work}
vmap work work
vlog -work work [file join $here ../../rtl/sync_fifo.v] [file join $here tb_fifo_basic.v]
vsim -voptargs=+acc work.tb_fifo_basic
onfinish stop
view wave
add wave /tb_fifo_basic/clk /tb_fifo_basic/rst_n
add wave /tb_fifo_basic/wr_en /tb_fifo_basic/rd_en
add wave -radix hexadecimal /tb_fifo_basic/din /tb_fifo_basic/dout
add wave -radix unsigned /tb_fifo_basic/count
add wave /tb_fifo_basic/full /tb_fifo_basic/empty
add wave -radix unsigned /tb_fifo_basic/dut/wr_ptr /tb_fifo_basic/dut/rd_ptr
add wave -radix unsigned /tb_fifo_basic/errors
run -all
wave zoom full
