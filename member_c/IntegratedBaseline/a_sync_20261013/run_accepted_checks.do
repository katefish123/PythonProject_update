onerror {quit -f -code 1}
onbreak {resume}
set root [pwd]
cd [file join $root accepted]
set libdir [file join $root verification work]
file mkdir [file dirname $libdir]
if {![file exists $libdir]} {vlib $libdir}
vmap a_accepted $libdir
set sources [glob vendor/b/rtl/*.v]
lappend sources rtl/algo/marker_detector.v vendor/c_current/01_design_code/video_timing_vtc.v
foreach path [glob rtl/memory/*.v] {lappend sources $path}
foreach path {rtl/video/ddr_snapshot_capture.v rtl/video/ddr_result_display.v rtl/top/frame_processor.v rtl/top/frame_session.v rtl/top/video_correct_ddr_core.v} {lappend sources $path}
set tests {tb_ddr_word_engine tb_ddr_pixel_cache tb_ddr_helpers tb_ddr_capture tb_ddr_display tb_video_correct_ddr_core}
foreach name $tests {lappend sources sim/$name.sv}
vlog -sv -work a_accepted {*}$sources
foreach name $tests {
 vsim -voptargs=+acc a_accepted.$name
 onfinish stop
 run -all
 if {$name in {tb_ddr_capture tb_ddr_display tb_video_correct_ddr_core}} {
  set passed [examine -value -radix binary -noshowbase sim:/$name/test_passed]
  if {[llength $passed]!=1 || [lindex $passed 0] ne "1"} {quit -f -code 1}
 }
 quit -sim
}
quit -f -code 0
