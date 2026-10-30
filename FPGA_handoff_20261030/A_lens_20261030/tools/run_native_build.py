"""Build only: compilation, mapping, routing, reports and paired CRAM files.

Never accesses a board. A successful tool exit does not qualify timing or optics.
"""
from pathlib import Path
import datetime
import hashlib
import json
import subprocess
import time
import argparse

ROOT=Path(__file__).resolve().parents[1]
R=ROOT/'candidate_host_angle_v2_product_stage'
TOOL=Path('C:/pango/PDS_2022.2-SP6.4/bin/pds_shell.exe')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    global R
    ap=argparse.ArgumentParser();ap.add_argument('--candidate',type=Path,default=R);a=ap.parse_args();R=a.candidate.resolve()
    manifest=R/'project/source_manifest.json'
    m=json.loads(manifest.read_text())
    inputs={p.name:sha(p) for p in (R/'sources').iterdir() if p.is_file()}
    assert inputs==m['source_sha256']
    script=R/'project/build_full.tcl'
    assert sha(script)==m['build_tcl_sha256']
    folder=R/'build'/('pds_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    folder.mkdir()
    argv=[TOOL.as_posix(),'-project_name','Lens_Angle_1080p30','-work_dir',folder.as_posix(),'-file',script.as_posix()]
    record={'status':'running','hardware_accessed':False,'qualified':False,
            'source_sha256':inputs,'manifest_sha256':sha(manifest),'build_tcl_sha256':sha(script),
            'driver_sha256':sha(Path(__file__)),'argv':argv,'build':str(folder)}
    state=folder/'offline_build_inputs.json'
    state.write_text(json.dumps(record,indent=2))
    print('NATIVE_BUILD '+str(folder),flush=True)
    started=time.time()
    with (folder/'build.log').open('w',encoding='utf-8') as log:
        result=subprocess.run(argv,cwd=folder,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
    record.update(status='completed' if result.returncode==0 else 'failed',returncode=result.returncode,
                  elapsed_seconds=time.time()-started,log_sha256=sha(folder/'build.log'),
                  sources_unchanged=inputs=={p.name:sha(p) for p in (R/'sources').iterdir() if p.is_file()})
    state.write_text(json.dumps(record,indent=2))
    print(json.dumps({k:record[k] for k in ['status','returncode','elapsed_seconds','sources_unchanged']},indent=2),flush=True)
    raise SystemExit(result.returncode if result.returncode else (0 if record['sources_unchanged'] else 1))


if __name__=='__main__':main()
