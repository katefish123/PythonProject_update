"""Extend the bound PDS release with independent alternating-frame evidence."""
import argparse,hashlib,json,shutil,subprocess,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--build',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 metrics=a.root/'fullhd_pipeline_metrics.json'
 subprocess.run([sys.executable,str(HERE/'measure.py'),'--root',str(a.root),'--output',str(metrics)],check=True)
 subprocess.run([sys.executable,str(HERE.parent/'a_sync_20261013/package_hires_reproduction.py'),'--root',str(a.root),'--build',str(a.build),'--output',str(a.output),'--expected-tests','27'],check=True)
 mp=a.output/'package_manifest.json';manifest=json.loads(mp.read_text())
 inputs=json.loads((a.root/'reproduction_manifest.json').read_text())['files']
 extras={'fullhd_pipeline_metrics.json':metrics}
 for name in ['pipeline_fixture.json','source_variant_1920x1080.png','expected_variant_640x904.png']:
  src=a.root/'fullhd_tests'/name
  if digest(src)!=inputs['fullhd_tests/'+name]['local_sha256']:raise RuntimeError('Variant evidence changed')
  extras['fixture/'+name]=src
 for name,src in extras.items():
  dst=a.output/name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst);manifest['files'][name]=digest(dst)
 mp.write_text(json.dumps(manifest,indent=2)+'\n')
 print('FULLHD_PIPELINE_PACKAGE_VERIFIED hardware_accepted=false')
if __name__=='__main__':main()
