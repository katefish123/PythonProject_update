"""Rebuild pinned A inputs, then apply C's explicitly versioned full-HD overlays."""
from pathlib import Path
import argparse, subprocess, sys, shutil, hashlib, json

HERE = Path(__file__).resolve().parent
BASE = HERE.parent / 'a_sync_20261013'
def main():
    p=argparse.ArgumentParser(); p.add_argument('--output',type=Path,required=True)
    args=p.parse_args(); out=args.output.resolve()
    subprocess.run([sys.executable,str(BASE/'prepare_hires_reproduction.py'),'--output',str(out)],check=True)
    overlays=HERE/'overrides'
    if overlays.exists():
        for src in overlays.rglob('*'):
            if src.is_file():
                dst=out/src.relative_to(overlays);dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
    subprocess.run([sys.executable,str(HERE/'prepare_tests.py'),'--output',str(out)],check=True)
    subprocess.run([sys.executable,str(HERE/'prepare_fixture.py'),'--output',str(out)],check=True)
    mp=out/'reproduction_manifest.json';m=json.loads(mp.read_text())
    m['path_relocation_only']=False;m['configuration']='fullhd_source_portrait'
    for name in m['files']:
        m['files'][name]['local_sha256']=hashlib.sha256((out/name).read_bytes()).hexdigest()
    for src in (out/'fullhd_tests').rglob('*'):
        if src.is_file() and src.suffix in {'.sv','.do','.hex','.json','.py','.png'}:
            m['files'][src.relative_to(out).as_posix()]={'local_sha256':hashlib.sha256(src.read_bytes()).hexdigest()}
    for src in (out/'diagnostics/ddr_camera_hires_prefetch_20261012/results').glob('*.do'):
        name=src.relative_to(out).as_posix()
        if name not in m['files']:m['files'][name]={'local_sha256':hashlib.sha256(src.read_bytes()).hexdigest()}
    mp.write_text(json.dumps(m,indent=2)+'\n')
if __name__=='__main__':main()
