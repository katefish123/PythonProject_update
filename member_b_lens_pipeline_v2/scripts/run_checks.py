"""One-command, fail-fast Python/RTL validation. Always checks RTL actual dumps."""
import argparse
import ast
import hashlib
import json
import re
import shutil
import subprocess
import sys
from datetime import datetime,timezone
from pathlib import Path
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"python"))
from brect.fixed import map_fixed
from generate_vectors import generate
from generate_lens_vectors import generate as generate_lens
from generate_autocrop_vectors import generate as generate_autocrop


def run(cmd,log):
    result=subprocess.run(cmd,cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120)
    (ROOT/"results"/log).write_text(result.stdout,encoding="utf-8")
    if result.returncode:
        raise RuntimeError(f"Command failed: {' '.join(map(str,cmd))}\n{result.stdout}")
    return result.stdout


def compare_dumps():
    expected={}
    for line in (ROOT/"vectors/coord.txt").read_text().splitlines():
        a=line.split();tag=int(a[3]);h=[int(v,16) for v in a[4:13]]
        h=[v-(1<<40) if v&(1<<39) else v for v in h]
        qx,qy,ok=map_fixed(h,int(a[1]),int(a[2]));expected[tag]=(qx,qy,int(not ok))
    coord=[line.split(",") for line in (ROOT/"results/rtl_coord.csv").read_text().splitlines()]
    if len(coord)!=len(expected):raise AssertionError("RTL coordinate count")
    for tag,qx,qy,e in coord:
        if expected.pop(int(tag))!=(int(qx),int(qy),int(e)):raise AssertionError("Python vs actual RTL coordinate dump")
    if expected:raise AssertionError("missing coordinate tags")
    rgb_expected={}
    for line in (ROOT/"vectors/interp.txt").read_text().splitlines():
        a=line.split();rgb_expected[int(a[1])]=int(a[-1],16)
    rows=(ROOT/"results/rtl_interp.csv").read_text().splitlines()
    if len(rows)!=len(rgb_expected):raise AssertionError("RTL interpolation count")
    for line in rows:
        tag,rgb=line.split(",")
        if rgb_expected.pop(int(tag))!=int(rgb,16):raise AssertionError("Python vs actual RTL RGB dump")
    files={0:"expected0",1:"precommit",2:"expected1",3:"hold"}
    pixels={k:[int(v,16) for v in (ROOT/f"vectors/{f}.hex").read_text().splitlines()] for k,f in files.items()}
    seen={-1:0,0:0,1:0,2:0,3:0,4:0};reconstructed={0:[],2:[]}
    for line in (ROOT/"results/rtl_video.csv").read_text().splitlines():
        ph,index,tag,rgb=line.split(",");ph,index,tag=int(ph),int(index),int(tag);rgb=int(rgb,16)
        exp=0 if ph in (-1,4) else pixels[ph][index]
        if rgb!=exp or tag!=(((index//32)<<12)|(index%32)):raise AssertionError("Python vs actual RTL video dump")
        seen[ph]+=1
        if ph in reconstructed:reconstructed[ph].append([rgb>>16,(rgb>>8)&255,rgb&255])
    if seen!={-1:16,0:768,1:8,2:768,3:768,4:16}:raise AssertionError(f"RTL video counts {seen}")
    for ph,vals in reconstructed.items():
        Image.fromarray(np.asarray(vals,np.uint8).reshape(24,32,3)).save(ROOT/f"results/rtl_rectified{ph}.png")
    # Independent Python re-check of actual solver output, including hold on error.
    source=(ROOT/"vectors/solver.txt").read_text().splitlines()
    solver=(ROOT/"results/rtl_solver.csv").read_text().splitlines()
    if len(source)!=len(solver):raise AssertionError("RTL solver count")
    for line,actual in zip(source,solver):
        a=line.split();b=[int(v) for v in actual.split(",")]
        if int(a[8])!=b[1]:raise AssertionError("solver error")
        if not b[1]:
            h=[int(v,16) for v in a[9:]];h=[v-(1<<40) if v&(1<<39) else v for v in h]
            if h!=b[2:]:raise AssertionError("RTL solver coefficients")
    lens_expected=[line.split() for line in (ROOT/"vectors/lens_integration.txt").read_text().splitlines()]
    lens_actual=(ROOT/"results/rtl_lens_video.csv").read_text().splitlines()
    if len(lens_actual)!=len(lens_expected):raise AssertionError("RTL lens output count")
    for index,(expected,actual) in enumerate(zip(lens_expected,lens_actual)):
        got_index,tag,rgb=actual.split(",")
        if int(got_index)!=index or int(tag)!=((int(expected[1])<<12)|int(expected[0])) or int(rgb,16)!=int(expected[-1]):
            raise AssertionError(f"Python vs actual combined H/lens/cache/interpolation dump at {index}")
    return {"coordinates":len(coord),"interpolations":len(rows),"solver_cases":len(solver),"video_pixels":sum(seen.values()),"lens_composed_pixels":len(lens_actual)}


def v3_check(path):
    if not path:return {"status":"not_requested"}
    import importlib.util
    spec=importlib.util.spec_from_file_location("user_v3",path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    from brect.fixed import sample_fixed
    rng=np.random.default_rng(676)
    image=rng.integers(0,256,(32,40,3),dtype=np.uint8)
    for _ in range(500):
        x,y=int(rng.integers(-256,41*256)),int(rng.integers(-256,33*256))
        np.testing.assert_array_equal(sample_fixed(image,x,y),module.sample_bilinear_q(image,x<<8,y<<8))
    return {"status":"pass","samples":500,"source":str(Path(path).resolve()),"sha256":hashlib.sha256(Path(path).read_bytes()).hexdigest()}


def test_targets():
    targets = []
    for line in (ROOT/"sim/tests.list").read_text().splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        fields = line.split()
        if len(fields) != 2:
            raise ValueError(f"invalid tests.list row: {line!r}")
        top, marker = fields
        if not re.fullmatch(r"tb_[a-z_]+", top) or not re.fullmatch(r"[A-Z][A-Z0-9_]*", marker):
            raise ValueError(f"invalid test target: {line!r}")
        if not (ROOT/f"sim/{top}.sv").is_file() or any(t == top for t, _ in targets):
            raise ValueError(f"missing or duplicate test target: {top}")
        targets.append((top, marker))
    if not targets:
        raise ValueError("tests.list is empty")
    available={p.stem for p in (ROOT/"sim").glob("tb_*.sv")}
    if {top for top,_ in targets} != available:
        raise ValueError("tests.list must include every sim/tb_*.sv exactly once")
    return targets


def main():
    ap=argparse.ArgumentParser();ap.add_argument("--python-only",action="store_true");ap.add_argument("--v3",type=Path);args=ap.parse_args()
    (ROOT/"results").mkdir(exist_ok=True)
    report={"status":"running","generated_utc":datetime.now(timezone.utc).isoformat(),"limitations":["PDS synthesis/place-route/Fmax not run","Native ModelSim execution is not performed by this Icarus runner","Board/camera/DDR/HDMI not tested"]}
    report_path=ROOT/"results/verification.json"
    report_path.write_text(json.dumps(report,indent=2))
    try:
        for path in list((ROOT/"python").rglob("*.py"))+list((ROOT/"scripts").glob("*.py")):
            ast.parse(path.read_text(),filename=str(path))
        report["python_syntax"]="pass"
        targets=test_targets();report["test_targets"]=[top for top,_ in targets]
        report["test_manifest_sha256"]=hashlib.sha256((ROOT/"sim/tests.list").read_bytes()).hexdigest()
        report["integration_example_sha256"]=hashlib.sha256((ROOT/"examples/b_rectifier_instance.v").read_bytes()).hexdigest()
        manifest=generate();report["float_fixed"]=manifest["metrics"]
        model_log=run([sys.executable,"-B","scripts/test_models.py","-v"],"python_tests.log")
        report["python_tests"]=int(re.search(r"Ran (\d+) tests",model_log)[1])
        lens_log=run([sys.executable,"-B","scripts/test_lens.py"],"lens_python_tests.log")
        report["lens_python_tests"]=int(re.search(r"Ran (\d+) tests",lens_log)[1])
        skipped=re.search(r"skipped=(\d+)",lens_log)
        report["lens_python_skipped"]=int(skipped[1]) if skipped else 0
        if report["lens_python_skipped"]:
            report["lens_opencv_oracle"]={"status":"not_run","reason":"required lens acceptance test skipped"}
            raise RuntimeError("Required lens acceptance tests were skipped. Install the independent OpenCV oracle with: pip install opencv-python; then rerun checks.")
        report["lens_opencv_oracle"]={"status":"pass"}
        viewport_log=run([sys.executable,"-B","scripts/test_viewport.py","-v"],"viewport_python_tests.log")
        report["viewport_python_tests"]=int(re.search(r"Ran (\d+) tests",viewport_log)[1])
        run([sys.executable,"-B","scripts/export_calibration.py","--calibration","calibration/r50_18mm_hdmi_trial.json","--output-prefix","examples/r50_18mm_calibration"],"lens_export.log")
        report["lens_vectors"]=generate_lens()
        report["autocrop_vectors"]=generate_autocrop()
        report["autocrop_build_inputs_sha256"]={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest()
            for name in ("examples/r50_18mm_viewport.vh","examples/r50_18mm_viewport.json",
                         "examples/lens_autocrop_instance.v","examples/autocrop_files.f",
                         "calibration/r50_18mm_hdmi_trial.json","vectors/lens_autocrop.txt")}
        report["modelsim_script_sha256"]=hashlib.sha256((ROOT/"run_modelsim.do").read_bytes()).hexdigest()
        if shutil.which("tclsh"):
            script_log=run([sys.executable,"-B","scripts/test_modelsim_script.py","-v"],"modelsim_script_tests.log")
            report["modelsim_script_control"]={"status":"pass","tests":int(re.search(r"Ran (\d+) tests",script_log)[1]),
                                              "method":"Tcl command stubs; not native ModelSim compilation/simulation"}
        else:
            report["modelsim_script_control"]={"status":"not_run","reason":"standalone tclsh unavailable"}
        report["v3_compatibility"]=v3_check(args.v3)
        if args.python_only:
            report["rtl_status"]="not_run_requested_python_only"
        else:
            if not shutil.which("iverilog") or not shutil.which("vvp"):
                raise RuntimeError("iverilog/vvp not installed. Install Icarus or use --python-only explicitly; RTL is not verified in that mode.")
            rtl=sorted(str(p.relative_to(ROOT)) for p in (ROOT/"rtl").glob("*.v"))
            run(["iverilog","-g2005","-Wall","-s","b_rectifier","-o","results/syntax.vvp",*rtl],"rtl_syntax.log")
            report["rtl_syntax"]="Verilog-2001 pass; Icarus array sensitivity notices in log"
            run(["iverilog","-g2005","-Wall","-s","b_rectifier_instance","-o","results/example_syntax.vvp","-f","examples/integration_files.f"],"example_syntax.log")
            report["integration_example_syntax"]="Verilog-2001 pass"
            run(["iverilog","-g2005","-Wall","-s","lens_pipeline_instance","-o","results/lens_example_syntax.vvp","-f","examples/lens_files.f"],"lens_example_syntax.log")
            report["lens_example_syntax"]="Verilog-2001 pass; explicit H plus lens, no marker detector"
            run(["iverilog","-g2005","-Wall","-s","lens_autocrop_instance","-o","results/autocrop_example_syntax.vvp","-f","examples/autocrop_files.f"],"autocrop_example_syntax.log")
            report["autocrop_example_syntax"]="pass; one exported calibration/H/crop binding"
            rtl.append("examples/lens_autocrop_instance.v")
            report["rtl_test_results"]={}
            for top,marker in targets:
                compiled=f"results/{top}.vvp"
                run(["iverilog","-g2012","-s",top,"-o",compiled,*rtl,f"sim/{top}.sv"],f"{top}_compile.log")
                output=run(["vvp",compiled],f"{top}.log")
                match=re.search(rf"(?m)^{re.escape(marker)}(?:\s|$).*$",output)
                if not match:raise AssertionError(f"missing success marker {top}")
                report["rtl_test_results"][top]={"status":"pass","marker":match.group(0),"log":f"results/{top}.log"}
                print(match.group(0))
            report["rtl_status"]="pass";report["actual_rtl_comparison"]=compare_dumps()
        report["status"]="pass"
        report["source_sha256"]={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
                                for sub in ("rtl","python","sim","scripts") for p in sorted((ROOT/sub).rglob("*")) if p.is_file() and p.suffix in (".py",".v",".sv")}
        print("ALL_CHECKS_PASS" if not args.python_only else "PYTHON_ONLY_PASS RTL_NOT_RUN")
    except Exception as error:
        report["status"]="fail";report["error"]=str(error)
        raise
    finally:
        report_path.write_text(json.dumps(report,indent=2),encoding="utf-8")


if __name__=="__main__":main()
