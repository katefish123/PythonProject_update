"""Confirm actual Git blobs retain the evidence/source/bitstream byte hashes."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

PREFIX='member_c/IntegratedBaseline/black_board_20261015'


def main():
    p=argparse.ArgumentParser();p.add_argument('--ref',default=':');a=p.parse_args()
    def blob(name):
        spec=(':'+name) if a.ref==':' else a.ref+':'+name
        return subprocess.check_output(['git','show',spec])
    def data(name):return json.loads(blob(name).decode('utf-8-sig'))
    count=0
    def check(name,expected):
        nonlocal count
        assert hashlib.sha256(blob(name)).hexdigest()==expected,name
        count+=1
    for folder in ['clock_validation','delivery']:
        m=data(PREFIX+'/'+folder+'/manifest.json')
        for name,digest in m['files'].items():check(PREFIX+'/'+folder+'/'+name,digest)
    m=data(PREFIX+'/clock_sources/source_manifest.json')
    for name,digest in m['files'].items():check(PREFIX+'/clock_sources/'+name,digest)
    m=data(PREFIX+'/board_snapshot/manifest.json')
    for name,digest in m['files'].items():check(PREFIX+'/board_snapshot/'+name,digest)
    lens='member_c/IntegratedBaseline/lens_model_20261015'
    m=data(lens+'/verification.json')
    for name,digest in m['source_sha256'].items():check(lens+'/'+name,digest)
    print('GIT_EVIDENCE_BLOBS_VERIFIED ref='+a.ref+' files='+str(count))


if __name__=='__main__':main()
