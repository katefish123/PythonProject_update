"""Read-only verification of archived telemetry timing-prefetch evidence."""
from pathlib import Path
import argparse,hashlib,json,re
HERE=Path(__file__).resolve().parent

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def recorded_hashes(p):
    records={}
    for block in re.split(r'\r?\n\s*\r?\n',p.read_text(encoding='utf-8-sig')):
        h=re.search(r'Hash\s*:\s*([a-fA-F0-9]{64})',block)
        name=re.search(r'Path\s*:\s*(.*)',block,re.S)
        if h and name:records[Path(''.join(t.strip() for t in name[1].splitlines())).name]=h[1].lower()
    assert records,'empty runtime source hash file'
    return records

def verify(folder):
    m=json.loads((folder/'manifest.json').read_text())
    assert m['current_rtl_sha256']=='b9c84822b38ab4cf6ad813733cc03ff41eb44c41882d65f33769eea513ecfc0e'
    for name,digest in m['archive_files_sha256'].items():
        p=(folder/name).resolve();assert p.is_relative_to(folder.resolve()),name
        assert sha(p)==digest,'archive changed: '+name
    for name,digest in m['current_source_sha256'].items():
        assert sha(HERE/name)==digest,'current source differs from archived evidence: '+name
    original=(folder/'sources/current/frame_telemetry_overlay.v').read_text()
    transformations={
      'glyphoffset':('on=active_row[4-dx[3:1]]',"on=active_row[4-((dx[3:1]+1'b1)&3'h7)]"),
      'midframe':('if(scan_start && req_sync[2]!=ack_pix)','if(req_sync[2]!=ack_pix)'),
      'noack':(' && ack_sync[2]==req_proc','')}
    for case in m['cases']:
        c=folder/case['archive_directory']
        compile_log=(c/'compile.log').read_text(encoding='utf-8-sig')
        log=(c/'simulation.log').read_text(encoding='utf-8-sig')
        assert 'Errors: 0, Warnings: 0' in compile_log
        assert not re.search(r'\*\* (?:Fatal|Error|Warning):',compile_log)
        for source in case['sources']:
            assert sha(folder/source['archived_file'])==source['sha256']
        if case['outcome']=='pass':
            assert case['expected_marker'] in log
            assert 'Errors: 0, Warnings: 0' in log
            assert not re.search(r'\*\* (?:Fatal|Error|Warning):',log)
            recorded=recorded_hashes(c/'source_hashes.txt')
            assert recorded=={Path(x['archived_file']).name:x['sha256'] for x in case['sources']}
        else:
            assert case['outcome']=='expected_failure'
            fatal=re.findall(r'^# \*\* Fatal: (.*)$',log,re.M)
            assert len(fatal)==1 and case['expected_marker'] in fatal[0],case['name']
            assert 'Errors: 1, Warnings: 0' in log
            assert not re.search(r'\*\* (?:Error|Warning):',log)
            assert 'PASS negative mutation caught: '+case['mutation'] in (c/'mutation_result.txt').read_text()
            old,new=transformations[case['mutation']]
            assert original.count(old)==1
            mutant=next(x for x in case['sources'] if x['archived_file'].endswith('.v'))
            assert (folder/mutant['archived_file']).read_text()==original.replace(old,new)
            for phase in ['before','after']:
                hashes=json.loads((folder/f'mutation_source_hashes_{phase}.json').read_text())
                assert hashes=={k:v for k,v in m['current_source_sha256'].items() if k!='verify_timing_results.py'}
    assert len(m['cases'])==6
    print('PASS timing-prefetch evidence: 3 positive runs, 3 expected negative failures; archive/current/runtime hashes match; frozen RTL unchanged')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--evidence',type=Path,default=HERE/'evidence/timing_prefetch')
    verify(p.parse_args().evidence.resolve())
