# Start with directed boundary tests. Use run -all for the remaining checks.
# ModelSim's do macro does not reliably expose its filename via info script.
set here C:/D/FPGA/demo/Projects/sync_fifo_demo/sim/boundary
quit -sim
cd $here
if {![file exists work]} {vlib work}
vmap work work
vlog -work work [file join $here ../../rtl/sync_fifo.v] [file join $here tb_sync_fifo.v]
vsim -voptargs=+acc work.tb_sync_fifo
onfinish stop
view wave
add wave /tb_sync_fifo/clk /tb_sync_fifo/rst_n
add wave /tb_sync_fifo/wr_en /tb_sync_fifo/rd_en
add wave -radix hexadecimal /tb_sync_fifo/din /tb_sync_fifo/dout
add wave -radix unsigned /tb_sync_fifo/count
add wave /tb_sync_fifo/full /tb_sync_fifo/empty
add wave -radix unsigned /tb_sync_fifo/dut/wr_ptr /tb_sync_fifo/dut/rd_ptr
add wave -radix unsigned /tb_sync_fifo/errors /tb_sync_fifo/checks
run 600 ns
wave zoom full
