"""Add native full-HD, multi-frame core/engine/scanout benchmarks."""
import argparse,hashlib,json,subprocess,sys,shutil
from pathlib import Path
import numpy as np
from PIL import Image
HERE=Path(__file__).resolve().parent
CAND='diagnostics/ddr_camera_hires_prefetch_20261012/results'
def main():
 p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args();out=a.output.resolve()
 subprocess.run([sys.executable,str(HERE.parent/'capture_overlap_20261014/prepare.py'),'--output',str(out)],check=True)
 for src in (HERE/'overrides').rglob('*'):
  if src.is_file():
   dst=out/src.relative_to(HERE/'overrides');dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
 for src in (out/'fullhd_tests').glob('*.sv'):
  code=src.read_text()
  if 'frame_session_overlap #' in code:code=code.replace('.capture_bank(','.capture_permitted(1\'b1),.capture_bank(')
  src.write_text(code)
 tests=out/'fullhd_tests';cand=out/CAND
 sys.path.insert(0,str(tests/'reference'))
 from brect.fixed import rectify_fixed
 from brect.golden import detect_markers
 image=np.array(Image.open(tests/'source_1920x1080.png'))
 gray=(image[:,:,0]==image[:,:,1])&(image[:,:,1]==image[:,:,2])
 image[gray]=image[gray]+16
 points,stats=detect_markers(image,min_pixels=64,max_pixels=16384,max_span=256)
 expected,coefficients=rectify_fixed(image,points,640,904,method='bilinear')
 for name,pixels in [('source_variant_1920x1080',image),('expected_variant_640x904',expected)]:
  packed=(pixels[:,:,0].astype(np.uint32)<<16)|(pixels[:,:,1].astype(np.uint32)<<8)|pixels[:,:,2]
  np.savetxt(tests/(name+'.hex'),packed.reshape(-1),fmt='%06x');Image.fromarray(pixels).save(tests/(name+'.png'))
 (tests/'pipeline_fixture.json').write_text(json.dumps(dict(points=points.tolist(),stats=stats,coefficients=coefficients,variant='non-marker grayscale +16; alternating captures'),indent=2)+'\n')
 test=tests/'tb_fullhd_pipeline.sv';test.write_text((HERE/'tb_fullhd_pipeline.sv').read_text().replace('@ROOT@',out.as_posix()))
 template=(cand/'tb_scheduler.do').read_text().replace('tb_scheduler','tb_fullhd_pipeline').replace('work_scheduler','work_fullhd_pipeline')
 for mode in [0,1,2]:
  code=template.replace('work_fullhd_pipeline','work_fullhd_pipeline_'+str(mode))
  flags=f'-gOVERLAP={int(mode>0)} -gPREFETCH={int(mode==2)} -gLATE_CAPTURE={95 if mode==2 else 0}'
  code=code.replace('-voptargs=+acc','-voptargs=+acc=rnp+/tb_fullhd_pipeline').replace(' work_fullhd_pipeline_'+str(mode)+'.tb_fullhd_pipeline',f' {flags} work_fullhd_pipeline_{mode}.tb_fullhd_pipeline')
  code=code.replace('tb_fullhd_pipeline.transcript.log',f'tb_fullhd_pipeline_{mode}.transcript.log').replace('tb_fullhd_pipeline.wlf',f'tb_fullhd_pipeline_{mode}.wlf')
  (cand/f'tb_fullhd_pipeline_{mode}.do').write_text(code)
 mpath=out/'reproduction_manifest.json';m=json.loads(mpath.read_text())
 for name in m['files']:m['files'][name]['local_sha256']=hashlib.sha256((out/name).read_bytes()).hexdigest()
 for src in [test,tests/'pipeline_fixture.json',*tests.glob('*variant*'),*cand.glob('tb_fullhd_pipeline_*.do')]:
  m['files'][src.relative_to(out).as_posix()]={'local_sha256':hashlib.sha256(src.read_bytes()).hexdigest()}
 mpath.write_text(json.dumps(m,indent=2)+'\n')
 cases=json.loads((cand/'simulation_cases.json').read_text())
 for mode in [0,1,2]:cases[f'tb_fullhd_pipeline_{mode}']='FULLHD_PIPELINE_PASS'
 for name,marker in [('tb_source_prefetch','SOURCE_PREFETCH_PASS'),('tb_late_capture','LATE_CAPTURE_PASS')]:
  dst=tests/(name+'.sv');shutil.copyfile(HERE/(name+'.sv'),dst)
  script=cand/(name+'.do');script.write_text(template.replace('tb_fullhd_pipeline',name).replace('work_fullhd_pipeline','work_'+name))
  cases[name]=marker
  for src in [dst,script]:m['files'][src.relative_to(out).as_posix()]={'local_sha256':hashlib.sha256(src.read_bytes()).hexdigest()}
 (cand/'simulation_cases.json').write_text(json.dumps(cases,indent=2)+'\n')
 # The case manifest was already bound; refresh its digest after adding cases.
 m['files'][(cand/'simulation_cases.json').relative_to(out).as_posix()]['local_sha256']=hashlib.sha256((cand/'simulation_cases.json').read_bytes()).hexdigest()
 mpath.write_text(json.dumps(m,indent=2)+'\n')
 print('FULLHD_PIPELINE_BENCH_READY frames=3 modes=serial,eager,late_prefetch tests=27 native_engine=1')
if __name__=='__main__':main()
