"""Prepare the full-HD baseline, then apply the bounded scheduling optimization."""
import argparse,hashlib,json,subprocess,sys,shutil
from pathlib import Path
HERE=Path(__file__).resolve().parent
def main():
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);args=p.parse_args();out=args.output.resolve()
    subprocess.run([sys.executable,str(HERE.parent/'fullhd_source_20261013/prepare.py'),'--output',str(out)],check=True)
    if (HERE/'overrides').exists():
        for src in (HERE/'overrides').rglob('*'):
            if src.is_file():
                dst=out/src.relative_to(HERE/'overrides');dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
    cand=out/'diagnostics/ddr_camera_hires_prefetch_20261012/results'
    frame=out/'fullhd_tests/tb_ddr_full_frame.sv'
    assert frame.read_text().count('  test_passed=1;') == 1, 'Expected one full-frame qualification point'
    text=frame.read_text().replace('  test_passed=1;', '  if(cycles>=24000000)$fatal(1,"PERFORMANCE_TARGET_MISSED cycles=%0d limit=24000000",cycles);\n  test_passed=1;')
    frame.write_text(text)
    test=out/'fullhd_tests/tb_scheduler.sv';shutil.copyfile(HERE/'tb_scheduler.sv',test)
    code=(cand/'tb_fullhd_frame.do').read_text().replace((out/'fullhd_tests/tb_ddr_full_frame.sv').as_posix(),test.as_posix())
    code=code.replace('work_fullhd_frame','work_scheduler').replace('tb_ddr_full_frame','tb_scheduler').replace('tb_fullhd_frame.transcript','tb_scheduler.transcript').replace('tb_fullhd_frame.wlf','tb_scheduler.wlf')
    (cand/'tb_scheduler.do').write_text(code)
    cases=json.loads((cand/'simulation_cases.json').read_text());cases['tb_scheduler']='SCHEDULER_BACKPRESSURE_RESET_PASS'
    (cand/'simulation_cases.json').write_text(json.dumps(cases,indent=2)+'\n')
    mp=out/'reproduction_manifest.json';m=json.loads(mp.read_text());m['configuration']='fullhd_source_portrait'
    m['optimization']='bounded_coordinate_prefetch_and_chained_pixel_reads'
    for name in m['files']:m['files'][name]['local_sha256']=hashlib.sha256((out/name).read_bytes()).hexdigest()
    for src in (test,cand/'tb_scheduler.do'):
        m['files'][src.relative_to(out).as_posix()]={'local_sha256':hashlib.sha256(src.read_bytes()).hexdigest()}
    mp.write_text(json.dumps(m,indent=2)+'\n')
if __name__=='__main__':main()
