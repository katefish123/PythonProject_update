# Run from package root: do run_modelsim.do
# Keep GUI open on success and error; stop on first failure.
onerror {abort}
onbreak {resume}
file mkdir results
transcript file results/modelsim_full.log
transcript on
if {![file exists work]} {vlib work}
vmap work work
# ModelSim 2020.4 receives an unexpanded Tcl list as ONE filename.
# Pass one source per call; also preserves paths containing spaces.
foreach source_file [lsort [glob rtl/*.v]] {
    vlog -work work $source_file
}
vlog -work work examples/b_rectifier_instance.v
vlog -work work examples/lens_pipeline_instance.v
vlog -work work examples/lens_autocrop_instance.v
foreach source_file [lsort [glob sim/*.sv]] {
    vlog -sv -work work $source_file
}
# Read the same ordered targets as scripts/run_checks.py. Fail on bad/empty lists.
set list_file [open sim/tests.list r]
set list_text [read $list_file]
close $list_file
set tops {}
foreach row [split $list_text "\n"] {
    set row [string trim $row]
    if {$row eq "" || [string index $row 0] eq "#"} {continue}
    set fields [regexp -all -inline {\S+} $row]
    if {[llength $fields] != 2} {error "invalid tests.list row: <$row>"}
    set top [lindex $fields 0]
    set marker [lindex $fields 1]
    if {![regexp {^tb_[a-z_]+$} $top] || ![regexp {^[A-Z][A-Z0-9_]*$} $marker]} {
        error "invalid tests.list target: <$row>"
    }
    if {![file isfile "sim/$top.sv"]} {error "missing testbench sim/$top.sv"}
    if {[lsearch -exact $tops $top] >= 0} {error "duplicate tests.list target: $top"}
    lappend tops $top
}
if {[llength $tops] == 0} {error "tests.list is empty"}
set available_tops {}
foreach source_file [glob -nocomplain sim/tb_*.sv] {
    lappend available_tops [file rootname [file tail $source_file]]
}
if {[lsort $tops] ne [lsort $available_tops]} {error "tests.list must include every sim/tb_*.sv exactly once"}
foreach top $tops {
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
