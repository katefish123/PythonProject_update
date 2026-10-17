quit -sim
cd C:/D/FPGA/demo/Projects/fifo_ip_demo/sim
if {![file exists work]} {vlib work}
vmap work work
set ip C:/D/FPGA/demo/Projects/fifo_ip_demo/ipcore/fifo_sync_8x512
set lib C:/pango/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation
vlog -work work +incdir+$ip/rtl $lib/GTP_GRS.v $lib/GTP_DRM18K_E1.v $ip/rtl/ipm2l_fifo_ctrl_v1_1_fifo_sync_8x512.v $ip/rtl/ipm2l_sdpram_v1_10_fifo_sync_8x512.v $ip/rtl/ipm2l_fifo_v1_10_fifo_sync_8x512.v $ip/fifo_sync_8x512.v ../rtl/fifo_ip_top.v tb_fifo_ip_boundary.v
vsim -wlf fifo_ip_boundary.wlf -voptargs=+acc work.tb_fifo_ip_boundary
onfinish stop
view wave
add wave /tb_fifo_ip_boundary/clk /tb_fifo_ip_boundary/rst_n
add wave /tb_fifo_ip_boundary/wr_en /tb_fifo_ip_boundary/rd_en
add wave /tb_fifo_ip_boundary/dut/write_accept /tb_fifo_ip_boundary/dut/read_accept
add wave -radix hexadecimal /tb_fifo_ip_boundary/din /tb_fifo_ip_boundary/dout
add wave -radix unsigned /tb_fifo_ip_boundary/wr_water_level /tb_fifo_ip_boundary/rd_water_level
add wave /tb_fifo_ip_boundary/full /tb_fifo_ip_boundary/empty
add wave /tb_fifo_ip_boundary/almost_full /tb_fifo_ip_boundary/almost_empty
add wave -radix unsigned /tb_fifo_ip_boundary/errors /tb_fifo_ip_boundary/checks
# Stop around the full boundary for teaching; run -all continues the test.
run 5300 ns
wave zoom range 5050ns 5250ns
