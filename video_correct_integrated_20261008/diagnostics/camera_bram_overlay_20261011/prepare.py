"""Keep the accepted BRAM image immutable; overlay actual status in a clone."""
from pathlib import Path
import difflib
import hashlib
import json
import zipfile

D = Path(__file__).resolve().parent
R = D.parents[1]
O = D / "results"
O.mkdir(exist_ok=True)
base = R / "release/camera_live_bram_reconnect_20261010"
qualified = json.loads((base / "build_qualification.json").read_text(encoding="utf-8-sig"))
assert qualified["simulations_passed"] and qualified["timing_passed"]
for name, digest in qualified["files"].items():
    assert hashlib.sha256((base / name).read_bytes()).hexdigest() == digest, name
manifest = json.loads((base / "source_hashes.json").read_text(encoding="utf-8-sig"))
sources, hashes, names = [], {}, set()
with zipfile.ZipFile(base / "source_snapshot.zip") as archive:
    assert archive.testzip() is None
    for original, digest in manifest.items():
        path = Path(original)
        assert path.name not in names
        names.add(path.name)
        data = archive.read(path.relative_to(R).as_posix())
        assert hashlib.sha256(data).hexdigest() == digest, original
        target = O / path.name
        if path.name == "camera_live_bram_top.v":
            original_top = data.decode("utf-8-sig")
            top = original_top
            changes = {
                "reg [2:0] hs_pipe,vs_pipe,de_pipe;": "reg [2:0] hs_pipe,vs_pipe,de_pipe,status_pipe;",
                "hs_pipe<=0;vs_pipe<=0;de_pipe<=0;": "hs_pipe<=0;vs_pipe<=0;de_pipe<=0;status_pipe<=0;",
                "de_pipe<={de_pipe[1:0],raw_de};": "de_pipe<={de_pipe[1:0],raw_de};\n   status_pipe<={status_pipe[1:0],status_area};",
                "(frame_valid?stored_pixel:fallback_2)": "((frame_valid&&!status_pipe[2])?stored_pixel:fallback_2)",
            }
            for old, new in changes.items():
                assert top.count(old) == 1, old
                top = top.replace(old, new)
            top = top.replace("// Without a fresh camera frame, show a diagnostic grid on a dark background.",
                "// Diagnostic clone: show actual status below y=840 even while camera frames arrive.")
            data = top.encode("utf-8")
            (O / "overlay.diff").write_text("".join(difflib.unified_diff(original_top.splitlines(True), top.splitlines(True),
                fromfile="retained_be1_top.v", tofile="isolated_overlay_top.v")), encoding="utf-8")
        target.write_bytes(data)
        hashes[str(target)] = hashlib.sha256(data).hexdigest()
        if target.suffix == ".v":
            sources.append(target)
        elif target.suffix == ".fdc":
            fdc = target
flow = ["set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676"]
flow += [f"add_design {{{p.as_posix()}}}" for p in sources]
flow += [f"add_constraint -logic -fdc {{{fdc.as_posix()}}}", "compile -top_module camera_live_bram_top",
    "synthesize -ads", "dev_map", "pnr", "report_timing", "gen_bit_stream"]
(O / "build.tcl").write_text("\n".join(flow) + "\n", encoding="utf-8")
(O / "source_hashes.json").write_text(json.dumps(hashes, indent=2) + "\n", encoding="utf-8")

tb = (R / "diagnostics/camera_live_bram_20261010/tb_camera_live_bram.v").read_text(encoding="utf-8-sig")
tb = tb.replace("tb_camera_live_bram", "tb_camera_bram_overlay")
tb = tb.replace("expected=source_pixel(tag,oy,ox);", """if(oy>=840) begin
    expected=dut.status_frame[319-((oy-840)/12)*16-(ox/120)]?24'h00b000:24'hb00000;
   end else expected=source_pixel(tag,oy,ox);""")
tb = tb.replace("PASS_RAW_CAMERA_FULL_1080P_FRAME", "PASS_LIVE_CAMERA_STATUS_OVERLAY_FULL_1080P")
(O / "tb_camera_bram_overlay.v").write_text(tb, encoding="utf-8")
files = ["camera_live_bram_top.v", "hdmi_bram_probe.v", "cdc_snapshot.v", "reset_sync.v", "video_timing_vtc.v", "tb_camera_bram_overlay.v"]
test = "tb_camera_bram_overlay"
lines = ["onerror {quit -f -code 1}", f"transcript file {test}.transcript.log",
    f"if {{![file isdirectory work_{test}]}} {{vlib work_{test}}}", f"vmap work_{test} work_{test}",
    f"vlog -sv -work work_{test} " + " ".join(files),
    f"vsim -c -voptargs=+acc -wlf {test}.wlf work_{test}.{test}", "onfinish stop", "run -all",
    f"if {{[examine -radix decimal sim:/{test}/test_failed] != 0}} {{quit -f -code 1}}",
    f"if {{[examine -radix decimal sim:/{test}/test_passed] != 1}} {{quit -f -code 1}}", "quit -f -code 0"]
(O / (test + ".do")).write_text("\n".join(lines) + "\n", encoding="utf-8")
for name in ["tb_hdmi_bram_probe", "tb_hdmi_bram_stale"]:
    (O / (name + ".v")).write_bytes((R / "diagnostics/camera_live_bram_20261010/results" / (name + ".v")).read_bytes())
    sim = ["onerror {quit -f -code 1}", f"transcript file {name}.transcript.log",
        f"if {{![file isdirectory work_{name}]}} {{vlib work_{name}}}", f"vmap work_{name} work_{name}",
        f"vlog -sv -work work_{name} hdmi_bram_probe.v {name}.v",
        f"vsim -c -voptargs=+acc -wlf {name}.wlf work_{name}.{name}", "onfinish stop", "run -all",
        f"if {{[examine -radix decimal sim:/{name}/test_failed] != 0}} {{quit -f -code 1}}",
        f"if {{[examine -radix decimal sim:/{name}/test_passed] != 1}} {{quit -f -code 1}}", "quit -f -code 0"]
    (O / (name + ".do")).write_text("\n".join(sim) + "\n", encoding="utf-8")
program = (R / "pds/program_camera_live_bram_reconnect.tcl").read_text(encoding="utf-8-sig")
assert "release camera_live_bram_reconnect_20261010" in program
program = program.replace("release camera_live_bram_reconnect_20261010", "release camera_bram_overlay_20261011")
program = program.replace("camera_live_bram_top_timing_summary_after_hold_fix.txt", "camera_live_bram_top.rtr")
(R / "pds/program_camera_bram_overlay.tcl").write_text(program, encoding="utf-8")
driver = (R / "scripts/program_camera_live_bram_reconnect.ps1").read_text(encoding="utf-8-sig")
driver = driver.replace("release\\camera_live_bram_reconnect_20261010", "release\\camera_bram_overlay_20261011")
driver = driver.replace("program_camera_live_bram_reconnect", "program_camera_bram_overlay")
driver = driver.replace("camera_live_bram_reconnect_program_", "camera_bram_overlay_program_")
(R / "scripts/program_camera_bram_overlay.ps1").write_text(driver, encoding="utf-8")
print("Prepared independent live status overlay; input/capture/configuration sources unchanged from be1.")
