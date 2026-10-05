"""Check the actual .do file through Tcl command stubs, without ModelSim.

This verifies argument boundaries and fail-fast script control only.
It does not compile Verilog or replace a native ModelSim simulation.
"""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOPS = ["tb_perspective_coord", "tb_homography_solver", "tb_bilinear_interp", "tb_marker_detector", "tb_b_rectifier"]
HARNESS = r'''
set active_top ""
proc event {kind value} {
    set f [open $::env(B_MODELSIM_TRACE) a]
    puts $f "$kind\t$value"
    close $f
}
proc onerror {action} {
    if {$action ne "abort"} {error "onerror must abort"}
}
proc onbreak {action} {
    if {$action ne "resume"} {error "macro must reach test_passed check after a simulator stop"}
}
proc vlib {path} {event library $path}
proc vmap {args} {event mapping $args}
proc vlog {args} {
    set source_files {}
    set sv 0
    for {set i 0} {$i < [llength $args]} {incr i} {
        set arg [lindex $args $i]
        if {$arg eq "-work"} {incr i; continue}
        if {$arg eq "-sv"} {set sv 1; continue}
        lappend source_files $arg
    }
    foreach source_file $source_files {
        # Exact Tcl argument boundary: a list of paths is NOT one file.
        if {![file isfile $source_file]} {
            error "Failed to open design unit file \"$source_file\" in read mode. No such file or directory."
        }
        if {[file extension $source_file] eq ".sv" && !$sv} {
            error "testbench requires -sv"
        }
        event compile $source_file
        if {[info exists ::env(B_MODELSIM_FAIL_COMPILE)] &&
            $source_file eq $::env(B_MODELSIM_FAIL_COMPILE)} {
            error "injected_compile_error"
        }
    }
}
proc vsim {args} {
    if {[lsearch -exact $args "-voptargs=+acc"] < 0} {error "test_passed visibility needs +acc"}
    set unit [lindex $args end]
    if {![regexp {^work\.(tb_[a-z_]+)$} $unit -> top]} {error "invalid simulation top"}
    set ::active_top $top
    event simulate $top
}
proc onfinish {mode} {
    if {$mode ne "stop"} {error "GUI must remain open"}
}
proc run {args} {
    if {$args ne "-all" || $::active_top eq ""} {error "invalid run"}
    event run $::active_top
}
proc examine {args} {
    set path [lindex $args end]
    if {$path ne "sim:/$::active_top/test_passed"} {error "wrong test_passed path"}
    event examine $::active_top
    set value 1
    if {[info exists ::env(B_MODELSIM_FAIL_TOP)] &&
        $::active_top eq $::env(B_MODELSIM_FAIL_TOP)} {
        set value 0
        if {[info exists ::env(B_MODELSIM_BAD_FLAG)]} {set value $::env(B_MODELSIM_BAD_FLAG)}
    }
    set radix_i [lsearch -exact $args "-radix"]
    set radix [lindex $args [expr {$radix_i+1}]]
    # Decimal display can sign-interpret a one-bit 1 as -1. The old
    # stub returned integer 1 and therefore missed the native failure.
    if {$radix eq "decimal" && $value eq "1"} {set value -1}
    if {[info exists ::env(B_MODELSIM_EXAMINE_STYLE)]} {
        switch -- $::env(B_MODELSIM_EXAMINE_STYLE) {
            braced {return [format "{%s}" $value]}
            whitespace {return [format "  { %s }  " $value]}
            multiple {return [list $value 0]}
            showbase {
                if {[lsearch -exact $args "-noshowbase"] < 0} {return [format "{1'b%s}" $value]}
            }
        }
    }
    return $value
}
proc quit {args} {
    if {$args ne "-sim"} {error "script must not close ModelSim GUI"}
    event unload $::active_top
    set ::active_top ""
}
proc echo {args} {event message [join $args " "]}
if {[catch {source $::env(B_MODELSIM_SCRIPT)} message]} {
    puts stderr $message
    exit 1
}
puts "MODELSIM_TCL_STUB_PASS"
'''


class ModelSimScript(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tcl = shutil.which("tclsh")
        if not cls.tcl:
            raise unittest.SkipTest("tclsh unavailable; ModelSim script control not checked")

    def invoke(self, root=ROOT, **injections):
        with tempfile.TemporaryDirectory(prefix="b-modelsim-test-") as tmp:
            base = Path(tmp)
            harness = base / "harness.tcl"
            trace = base / "trace.txt"
            harness.write_text(HARNESS)
            env = os.environ.copy()
            env.pop("B_MODELSIM_FAIL_COMPILE", None)
            env.pop("B_MODELSIM_FAIL_TOP", None)
            env.pop("B_MODELSIM_BAD_FLAG", None)
            env.pop("B_MODELSIM_EXAMINE_STYLE", None)
            env.update(B_MODELSIM_SCRIPT=str(root / "run_modelsim.do"), B_MODELSIM_TRACE=str(trace))
            env.update(injections)
            result = subprocess.run([self.tcl, str(harness)], cwd=root, env=env,
                                    capture_output=True, text=True, timeout=15)
            events = [line.split("\t", 1) for line in trace.read_text().splitlines()] if trace.exists() else []
            return result, events

    def test_every_source_is_a_separate_existing_filename(self):
        result, events = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "rtl").glob("*.v"))
        expected += sorted(str(p.relative_to(ROOT)) for p in (ROOT / "sim").glob("*.sv"))
        self.assertEqual([value for kind, value in events if kind == "compile"], expected)
        self.assertEqual([value for kind, value in events if kind == "simulate"], TOPS)
        self.assertEqual([value for kind, value in events if kind == "unload"], TOPS)
        self.assertIn(["message", "ALL_MODELSIM_CHECKS_PASS"], events)

    def test_compile_failure_stops_before_any_simulation(self):
        result, events = self.invoke(B_MODELSIM_FAIL_COMPILE="rtl/bilinear_interp.v")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("injected_compile_error", result.stderr)
        self.assertFalse(any(kind == "simulate" for kind, _ in events))
        self.assertNotIn(["message", "ALL_MODELSIM_CHECKS_PASS"], events)

    def test_unpassed_testbench_stops_before_next_top(self):
        result, events = self.invoke(B_MODELSIM_FAIL_TOP=TOPS[1])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("did not set test_passed", result.stderr)
        self.assertEqual([value for kind, value in events if kind == "simulate"], TOPS[:2])
        self.assertNotIn(["message", "ALL_MODELSIM_CHECKS_PASS"], events)

    def test_one_bit_pass_does_not_use_signed_decimal_display(self):
        result, events = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(["message", "ALL_MODELSIM_CHECKS_PASS"], events)

    def test_single_value_tcl_list_formats_are_unwrapped(self):
        for style in ("braced", "whitespace", "showbase"):
            with self.subTest(style=style):
                result, events = self.invoke(B_MODELSIM_EXAMINE_STYLE=style)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(["message", "ALL_MODELSIM_CHECKS_PASS"], events)

    def test_zero_unknown_and_high_impedance_flags_are_failures(self):
        for value in ("0", "x", "z"):
            with self.subTest(value=value):
                result, events = self.invoke(B_MODELSIM_FAIL_TOP=TOPS[1], B_MODELSIM_BAD_FLAG=value,
                                             B_MODELSIM_EXAMINE_STYLE="braced")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("did not set test_passed", result.stderr)
                self.assertEqual([v for kind, v in events if kind == "simulate"], TOPS[:2])
                self.assertNotIn(["message", "ALL_MODELSIM_CHECKS_PASS"], events)

    def test_multiple_values_cannot_be_treated_as_one_pass_flag(self):
        result, events = self.invoke(B_MODELSIM_EXAMINE_STYLE="multiple")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(["message", "ALL_MODELSIM_CHECKS_PASS"], events)

    def test_package_directory_may_contain_spaces(self):
        with tempfile.TemporaryDirectory(prefix="b-modelsim-spaces-") as tmp:
            root = Path(tmp) / "project with spaces"
            root.mkdir()
            for name in ("rtl", "sim"):
                shutil.copytree(ROOT / name, root / name)
            shutil.copyfile(ROOT / "run_modelsim.do", root / "run_modelsim.do")
            result, events = self.invoke(root)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(["message", "ALL_MODELSIM_CHECKS_PASS"], events)


if __name__ == "__main__":
    unittest.main()
