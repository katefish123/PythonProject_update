onerror {quit -f -code 1}
onbreak {resume}
if {![file exists work_source_stream]} {vlib work_source_stream}
vmap work_source_stream work_source_stream
vlog -sv -work work_source_stream 01_design_code/hdmi_source_stream.v 02_simulation/tb_hdmi_source_stream.v
foreach size {{8 4} {1920 1080}} {
 vsim -voptargs=+acc -gW=[lindex $size 0] -gH=[lindex $size 1] work_source_stream.tb_hdmi_source_stream
 onfinish stop
 run -all
 if {[examine -radix decimal /tb_hdmi_source_stream/test_passed] != 1} {quit -f -code 1}
 quit -sim
}
quit -f -code 0
