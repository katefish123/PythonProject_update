"""Rebuild the frozen latency release and apply the isolated overlap candidate."""
import argparse,hashlib,json,subprocess,sys,shutil,re
from pathlib import Path
HERE=Path(__file__).resolve().parent
CAND='diagnostics/ddr_camera_hires_prefetch_20261012/results'
def main():
 p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);out=p.parse_args().output.resolve()
 subprocess.run([sys.executable,str(HERE.parent/'processing_speed_20261014/prepare.py'),'--output',str(out)],check=True)
 for src in (HERE/'overrides').rglob('*'):
  if src.is_file():
   dst=out/src.relative_to(HERE/'overrides');dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
 for test in out.rglob('*.sv'):
  text=test.read_text()
  text=text.replace('dut.session.state','dut.serial_session.session.state')
  if 'ddr_result_display #' in text:
   text=re.sub(r'(\.underrun\([^)]*\))(?!\s*,\s*\.prefetch_busy)',r'\1,.prefetch_busy()',text)
  test.write_text(text)
 cand=out/CAND;template=(cand/'tb_scheduler.do').read_text()
 cases=json.loads((cand/'simulation_cases.json').read_text())
 for name,marker in [('tb_overlap_session','OVERLAP_SESSION_PASS'),('tb_banked_writer','BANKED_WRITER_PASS')]:
  test=out/'fullhd_tests'/f'{name}.sv';shutil.copyfile(HERE/f'{name}.sv',test)
  (cand/f'{name}.do').write_text(template.replace('tb_scheduler',name).replace('work_scheduler','work_'+name))
  cases[name]=marker
 subprocess.run([sys.executable,str(HERE/'prepare_tests.py'),'--output',str(out)],check=True)
 for name,marker in [('tb_overlap_core','OVERLAP_CORE_PASS'),('tb_banked_capture_display','BANKED_FULLHD_CAPTURE_DISPLAY_PASS'),('tb_overlap_throughput','OVERLAP_THROUGHPUT_PASS')]:cases[name]=marker
 (cand/'simulation_cases.json').write_text(json.dumps(cases,indent=2)+'\n')
 for script in out.rglob('*.do'):
  code=script.read_text()
  code=re.sub(r'^vlib (\w+)\s*$',lambda x:'if {![file isdirectory '+x[1]+']} {vlib '+x[1]+'}',code,flags=re.M)
  script.write_text(code)
 mp=out/'reproduction_manifest.json';m=json.loads(mp.read_text());m['optimization']='two_source_banks_capture_processing_overlap'
 for name in m['files']:m['files'][name]['local_sha256']=hashlib.sha256((out/name).read_bytes()).hexdigest()
 for name in ['tb_overlap_session','tb_banked_writer','tb_overlap_core','tb_banked_capture_display','tb_overlap_throughput']:
  for src in [out/'fullhd_tests'/f'{name}.sv',cand/f'{name}.do']:m['files'][src.relative_to(out).as_posix()]={'local_sha256':hashlib.sha256(src.read_bytes()).hexdigest()}
 mp.write_text(json.dumps(m,indent=2)+'\n')
if __name__=='__main__':main()
