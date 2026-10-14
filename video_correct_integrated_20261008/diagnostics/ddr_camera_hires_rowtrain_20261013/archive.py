"""Seal only a fully verified independent row-train build, preserving older releases."""
from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,re,shutil,zipfile
D=Path(__file__).resolve().parent
R=D.parents[1]
O=D/'results'
release=R/'release/ddr_camera_hires_rowtrain_20261013'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):
    b=p.read_bytes()
    return b.decode('utf-16') if b.startswith((b'\xff\xfe',b'\xfe\xff')) else b.decode('utf-8-sig',errors='replace')
tests=json.loads(read(O/'simulation_qualification.json'))
assert len(tests['tests'])==14 and all(t['passed'] for t in tests['tests'].values())
for t in tests['tests'].values():
    p=Path(t['log']);assert sha(p)==t['log_sha256']
    s=read(p);assert t['pass_message'] in s and 'VERIFIED_PASS_BIT=1' in s
    assert not re.search(r'\*\* (Warning|Error|Fatal)|FAIL_',s)
timing=O/'report_timing/video_correct_ddr_top.rtr'
assert 'Design Summary : All Constraints Met.' in read(timing)
assert 'Executing : gen_bit_stream successfully.' in read(O/'build_run.log')
sources=json.loads(read(O/'source_hashes.json'))
baseline=json.loads(read(R/'release/ddr_camera_hires_prefetch_20261012/source_hashes.json'))
for p,h in baseline.items():assert sha(Path(p))==h,p
changed=[];unchanged=[]
for p,h in sources.items():
    p=Path(p);assert sha(p)==h,str(p)
    if p.parent==O:
        candidates=[Path(q) for q in baseline if Path(q).name==p.name]
        assert len(candidates)==1
        old_hash=baseline[str(candidates[0])]
    else:old_hash=baseline[str(p)]
    (changed if h!=old_hash else unchanged).append(str(p))
assert len(changed)==1 and Path(changed[0]).name=='ddr_result_display.v'
comparison=json.loads(read(O/'rowtrain_comparison.json'))
assert comparison['variants']['repaired']['black_pixels']==0 and comparison['variants']['repaired']['max_capture_backlog']<1024
bit=O/'generate_bitstream/video_correct_ddr_top.sbit';mask=bit.with_suffix('.smsk')
assert bit.stat().st_size==mask.stat().st_size==3791112
assert sha(bit)!='60fb0b53a5c13b2c1adf47539c66bb4426d967effa2e3f2a279a9cac09865f22'
release.mkdir(exist_ok=False)
for p in [bit,mask,timing,O/'source_hashes.json',O/'build_run.log',O/'simulation_qualification.json',O/'configuration.json',O/'fixture.json',O/'rowtrain_comparison.json']+[Path(t['log']) for t in tests['tests'].values()]:
    shutil.copyfile(p,release/p.name)
files=[Path(p) for p in sources]+list(D.glob('*.py'))+list(D.glob('*.ps1'))+list(D.glob('*.sv'))
files+=[O/'build.tcl',O/'simulation_cases.json',O/'ddr_camera_hires_rowtrain.pds']
files+=list(O.glob('tb*.sv'))+list(O.glob('tb*.do'))+list(O.glob('*.hex'))
files+=list((R/'vendor/b/vectors').glob('*.hex'))+list((R/'vendor/b/python').rglob('*.py'))
files+=[R/'pds/program_ddr_camera_hires_rowtrain.tcl',R/'scripts/program_ddr_camera_hires_rowtrain.ps1',
    R/'scripts/record_rowtrain_camera_program_20261013.py',R/'下载高清校正_行读取修复版.cmd',
    O/'rejected_simultaneous_overload_new.log',O/'simultaneous_overload_old_control.log']
files+=[R/'diagnostics/ddr_camera_hires_prefetch_20261012/results/ddr_result_display.v']
files+=[R/'scripts/publish_rowtrain_entry_20261013.py',R/'scripts/probe_rowtrain_video_20261013.py',R/'scripts/prepare_rowtrain_probe_20261013.py',R/'docs/高清行读取修复_20261013.md']
with zipfile.ZipFile(release/'source_snapshot.zip','x',zipfile.ZIP_DEFLATED) as z:
    for p in dict.fromkeys(files):z.write(p,p.relative_to(R).as_posix())
with zipfile.ZipFile(release/'source_snapshot.zip') as z:assert z.testzip() is None
record={'sealed_at_utc':datetime.now(timezone.utc).isoformat(),'simulations_passed':True,'timing_passed':True,
    'part':'PG2L100H -6 FBG676','top':'video_correct_ddr_top','tests':tests,'base_release':'release/ddr_camera_hires_prefetch_20261012',
    'source_sampling':[960,540],'processed_output':[640,904],'display':[1920,1080],'scale':1,
    'window':{'x':640,'y':88,'width':640,'height':904},'capture_fifo_packets':1024,
    'changed_sources':changed,'unchanged_compiled_source_count':len(unchanged),
    'change':'Only display scheduling changed: direct complete-beat line RAM store and immediately advertised next command, retaining display priority across an entire row. Single outstanding command, guarded late-beat store and full-line acknowledgement preserved. Result cache, HDMI, geometry, markers, capture and constraints unchanged.',
    'retained_verified_baseline':'results/hardware_20261009/baseline_recovered_verified_20261012.json',
    'previous_actual_failure':'results/hardware_20261009/prefetch_display_flicker_verified_20261013.json',
    'hardware_programmed':False,'actual_camera_correction_accepted':False,'clarity_improvement_accepted':False,'flash_modified':False,
    'performance_limit':'Memory delay and capture phase assumptions are simulation stress models, not measured board latency or algorithm FPS. Physical stability is pending.',
    'timing_limit':'Vendor DDR and provisional external HDMI IO timing models. All Constraints Met only under these models.',
    'files':{p.name:sha(p) for p in release.iterdir() if p.is_file()}}
(release/'build_qualification.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'release':str(release),'sha256':sha(release/bit.name),'changed_sources':len(changed),'unchanged_sources':len(unchanged)},indent=2))
