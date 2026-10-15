"""Archive actual filtered-clock acceptance, without publishing a board package."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path


def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--build',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    cand=a.root/'diagnostics/ddr_camera_hires_prefetch_20261012/results'
    qual=cand/'reproduced_simulation_qualification.json';q=json.loads(qual.read_text(encoding='utf-8-sig'))
    build=a.build/'build_qualification.json';b=json.loads(build.read_text(encoding='utf-8-sig'))
    manifest=a.root/'reproduction_manifest.json'
    assert q['status']=='passed' and len(q['tests'])==22
    assert b['simulations_passed'] and b['timing_passed'] and not b['hardware_accepted']
    assert b['source_manifest_sha256']==q['source_manifest_sha256']==sha(manifest)
    assert b['simulation_qualification_sha256']==sha(qual)
    for name,item in json.loads(manifest.read_text())['files'].items():assert sha(a.root/name)==item['local_sha256']
    timing=Path(b['timing_report']);assert 'Design Summary : All Constraints Met.' in timing.read_text()
    files={'simulation_qualification.json':qual,'build_qualification.json':build,'reproduction_manifest.json':manifest,
           'timing_passed.txt':timing,'performance.json':a.root/'performance.json'}
    for name,item in q['tests'].items():
        log=Path(item['log']);assert item['passed'] and item['exit_code']==0 and sha(log)==item['log_sha256']
        files['logs/'+name+'.log']=log
    a.output.mkdir(parents=True,exist_ok=False)
    for name,src in files.items():
        dst=a.output/name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
    (a.output/'manifest.json').write_text(json.dumps(dict(configuration='filtered_clock_only_not_merged_board_release',
        simulations_passed=22,timing_passed=True,hardware_accepted=False,board_replacement_allowed=False,
        unmerged=['540dd628 capture burst/preview/recovery changes'],files={name:sha(src) for name,src in files.items()}),indent=2)+'\n')
    print('CLOCK_EVIDENCE_ARCHIVED simulations=22 timing=passed board_replacement_allowed=false')


if __name__=='__main__':main()
