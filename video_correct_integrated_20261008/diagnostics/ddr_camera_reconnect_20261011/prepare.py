"""Shadow only the tested RX reconnect fix in a new full-DDR build."""
from pathlib import Path
import difflib
import hashlib
import json
import re

directory = Path(__file__).resolve().parent
root = directory.parents[1]
out = directory / "results"
out.mkdir(exist_ok=True)
baseline_path = root / "rtl/hdmi/ms7200_ctl.v"
baseline = baseline_path.read_text(encoding="utf-8-sig")
old = "(!init_over || ((freq_rec_2d[17:16] == 2'b00) && (freq_rec_1d[17:16] == 2'b10)))"
new = "(!init_over || (freq_rec_2d[17] == 1'b0))"
assert baseline.count(old) == 1
fixed = baseline.replace(old, new)
proven = root / "diagnostics/camera_native_rx_first_20261010/results/ms7200_ctl.v"
assert fixed == proven.read_text(encoding="utf-8-sig")
(out / "ms7200_ctl.v").write_text(fixed, encoding="utf-8")
(out / "ms7200_ctl_baseline.v").write_text(baseline, encoding="utf-8")
(out / "reconnect_change.diff").write_text("".join(difflib.unified_diff(baseline.splitlines(True), fixed.splitlines(True), fromfile="retained_main_ms7200_ctl.v", tofile="isolated_fixed_ms7200_ctl.v")), encoding="utf-8")

flow = (root / "pds/build_board_ddr.tcl").read_text(encoding="utf-8-sig")
old_design = f"add_design {{{baseline_path.as_posix()}}}"
new_design = f"add_design {{{(out / 'ms7200_ctl.v').as_posix()}}}"
assert flow.count(old_design) == 1
flow = flow.replace(old_design, new_design)
(out / "build.tcl").write_text(flow, encoding="utf-8")
paths = [Path(match[1]) for line in flow.splitlines() if (match := re.fullmatch(r"add_design \{(.+)\}", line))]
paths += [root / "constr/board_ddr.fdc"]
(out / "source_hashes.json").write_text(json.dumps({str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}, indent=2) + "\n", encoding="utf-8")

native = root / "diagnostics/camera_native_rx_first_20261010/results"
for name in ["hdmi_config.v", "ms7210_ctl.v", "iic_dri.v"]:
    (out / name).write_bytes((root / "rtl/hdmi" / name).read_bytes())
for name in ["ms72xx_i2c_test_device.sv", "tb_rx_reconnect.sv", "tb_hdmi_config.sv"]:
    (out / name).write_bytes((native / name).read_bytes())
cases = {
    "reconnect_hdmi_tx_first": ("tb_rx_reconnect", "-gTX_FIRST=1 -gINITIAL_STATUS=3", "TEST_PASS_TWO_RECONNECTS_WITHOUT_RESET"),
    "reconnect_dvi_tx_first": ("tb_rx_reconnect", "-gTX_FIRST=1 -gINITIAL_STATUS=2", "TEST_PASS_TWO_RECONNECTS_WITHOUT_RESET"),
    "startup_tx_first": ("tb_hdmi_config", "-gTX_FIRST=1", "TEST_PASS_NO_DEVICE"),
}
for name, (testbench, generics, marker) in cases.items():
    library = "work_" + name
    # tb_hdmi_config includes its own actual-I2C device model after the top
    # module. Avoid compiling a second definition and silently replacing it.
    external_model = "ms72xx_i2c_test_device.sv " if testbench == "tb_rx_reconnect" else ""
    lines = [
        "onerror {quit -f -code 1}", f"transcript file {name}.transcript.log",
        f"if {{![file isdirectory {library}]}} {{vlib {library}}}", f"vmap {library} {library}",
        f"vlog -sv -work {library} hdmi_config.v ms7200_ctl.v ms7210_ctl.v iic_dri.v {external_model}{testbench}.sv",
        f"vsim -c -voptargs=+acc -wlf {name}.wlf {generics} {library}.{testbench}",
        "onfinish stop", "run -all",
        f"if {{[examine -radix decimal sim:/{testbench}/test_failed] != 0}} {{quit -f -code 1}}", "quit -f -code 0",
    ]
    (out / (name + ".do")).write_text("\n".join(lines) + "\n", encoding="utf-8")
(out / "simulation_cases.json").write_text(json.dumps(cases, indent=2) + "\n", encoding="utf-8")
print("Prepared full-DDR shadow build and actual TX-first startup/reconnect checks. Retained main sources/releases unchanged.")
