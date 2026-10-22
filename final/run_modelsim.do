# Run from package root: do run_modelsim.do
# Keep GUI open on success and error; stop on first failure.
onerror {abort}
onbreak {resume}
if {![file exists work]} {vlib work}
vmap work work
# ModelSim 2020.4 receives an unexpanded Tcl list as ONE filename.
# Pass one source per call; also preserves paths containing spaces.
foreach source_file [lsort [glob rtl/*.v]] {
    vlog -work work $source_file
}
foreach source_file [lsort [glob sim/*.sv]] {
    vlog -sv -work work $source_file
}
foreach top {tb_perspective_coord tb_homography_solver tb_bilinear_interp tb_marker_detector tb_b_rectifier} {
    vsim -voptargs=+acc work.$top
    onfinish stop
    run -all
    # Read a single BIT, not signed decimal (a one-bit 1 may display as -1).
    # examine returns a Tcl list; extract its sole value before comparing.
    set pass_values [examine -value -radix binary -noshowbase sim:/$top/test_passed]
    if {[llength $pass_values] != 1} {
        error "$top returned unexpected test_passed values: <$pass_values>"
    }
    set pass_bit [string trim [lindex $pass_values 0]]
    echo "$top test_passed(binary)=<$pass_bit>"
    if {$pass_bit ne "1"} {
        error "$top did not set test_passed: binary=<$pass_bit>, raw=<$pass_values>"
    }
    echo "$top PASS"
    quit -sim
}
echo "ALL_MODELSIM_CHECKS_PASS"
