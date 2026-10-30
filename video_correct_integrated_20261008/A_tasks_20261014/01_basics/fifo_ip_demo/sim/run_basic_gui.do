# Absolute paths avoid the ModelSim do/info-script path issue.
quit -sim
cd C:/D/FPGA/demo/Projects/fifo_ip_demo/sim
if {![file exists work]} {vlib work}
vmap work work
set ip C:/D/FPGA/demo/Projects/fifo_ip_demo/ipcore/fifo_sync_8x512
set lib C:/pango/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation
vlog -work work +incdir+$ip/rtl $lib/GTP_GRS.v $lib/GTP_DRM18K_E1.v $ip/rtl/ipm2l_fifo_ctrl_v1_1_fifo_sync_8x512.v $ip/rtl/ipm2l_sdpram_v1_10_fifo_sync_8x512.v $ip/rtl/ipm2l_fifo_v1_10_fifo_sync_8x512.v $ip/fifo_sync_8x512.v ../rtl/fifo_ip_top.v tb_fifo_ip_basic.v
vsim -voptargs=+acc work.tb_fifo_ip_basic
onfinish stop
view wave
add wave /tb_fifo_ip_basic/clk /tb_fifo_ip_basic/rst_n /tb_fifo_ip_basic/dut/rst
add wave /tb_fifo_ip_basic/wr_en /tb_fifo_ip_basic/rd_en
add wave /tb_fifo_ip_basic/dut/write_accept /tb_fifo_ip_basic/dut/read_accept
add wave -radix hexadecimal /tb_fifo_ip_basic/din /tb_fifo_ip_basic/dout
add wave -radix unsigned /tb_fifo_ip_basic/wr_water_level /tb_fifo_ip_basic/rd_water_level
add wave /tb_fifo_ip_basic/full /tb_fifo_ip_basic/empty
add wave /tb_fifo_ip_basic/almost_full /tb_fifo_ip_basic/almost_empty
add wave -radix unsigned /tb_fifo_ip_basic/errors
run -all
wave zoom full
