onerror {quit -code 2 -force}
onbreak {resume}
onfinish stop
run -all
set b [examine -value -radix binary -noshowbase sim:/tb_frame_processor/test_passed]
if {[llength $b]!=1 || [lindex $b 0] ne "1"} {quit -code 3 -force}
quit -code 0 -force
