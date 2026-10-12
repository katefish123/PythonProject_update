onerror {quit -code 2 -force}
onbreak {resume}
onfinish stop
run -all
set p [examine -value -radix binary -noshowbase sim:/tb_video_correct_ddr_core/test_passed]
if {[llength $p]!=1 || [lindex $p 0] ne "1"} {quit -code 3 -force}
quit -code 0 -force
