onerror {quit -code 2 -force}
onbreak {resume}
onfinish stop
run -all
set bit [examine -value -radix binary -noshowbase sim:/tb_request_boundaries/test_passed]
if {[llength $bit] != 1 || [lindex $bit 0] ne "1"} {quit -code 3 -force}
echo "NATIVE_PASS_BIT=1"
quit -code 0 -force
