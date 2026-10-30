"""Seal only the qualified coordinate-lookahead build; board remains off."""
from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,re,shutil,zipfile
D=Path(__file__).resolve().parent
R=D.parents[1]
O=D/'results'
release=R/'release/ddr_camera_coordqueue_20261013'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):
    b=p.read_bytes()
    return b.decode('utf-16') if b.startswith((b'\xff\xfe',b'\xfe\xff')) else b.decode('utf-8-sig',errors='replace')
tests=json.loads(read(O/'simulation_qualification.json'))
assert len(tests['tests'])==15 and all(t['passed'] for t in tests['tests'].values())
for t in tests['tests'].values():
    p=Path(t['log']);assert sha(p)==t['log_sha256']
    s=read(p);assert t['pass_message'] in s and 'VERIFIED_PASS_BIT=1' in s
    assert not re.search(r'\*\* (Warning|Error|Fatal)|FAIL_',s)
profile=O/'tb_frame_profile.run.log'
assert 'PROFILE_TOTAL=25094025' in read(profile) and 'VERIFIED_PASS_BIT=1' in read(profile)
timing=O/'report_timing/video_correct_ddr_top.rtr'
assert 'Design Summary : All Constraints Met.' in read(timing)
assert 'Executing : gen_bit_stream successfully.' in read(O/'build_run.log')
sources=json.loads(read(O/'source_hashes.json'))
baseline=json.loads(read(R/'release/ddr_camera_hires_rowtrain_20261013/source_hashes.json'))
for p,h in baseline.items():assert sha(Path(p))==h,p
changed=[];unchanged=[]
for path,h in sources.items():
    p=Path(path);assert sha(p)==h,path
    if p.parent==O:
        old=[q for q in baseline if Path(q).name==p.name]
        assert len(old)==1
        original_hash=baseline[old[0]]
    else:original_hash=baseline[path]
    (changed if original_hash!=h else unchanged).append(path)
assert len(changed)==1 and Path(changed[0]).name=='frame_processor.v'
assert sha(O/'frame_processor.v')=='4d66c5165342ae0952b86aaa248d2421abe742d5cca5c8b31b098419b4869b6f'
comparison=json.loads(read(O/'coordinate_comparison.json'))
assert comparison['same_full_native_rgb'] and comparison['variants']['coordinate_lookahead']['total_cycles']==12365414
bit=O/'generate_bitstream/video_correct_ddr_top.sbit';mask=bit.with_suffix('.smsk')
assert bit.stat().st_size==mask.stat().st_size==3791112
assert sha(bit)!='eb06c8f9645665111b339e2ea305549a107830275d50f7625245b163b371d987'
release.mkdir(exist_ok=False)
for p in [bit,mask,timing,O/'source_hashes.json',O/'build_run.log',O/'simulation_qualification.json',O/'configuration.json',O/'fixture.json',O/'coordinate_comparison.json',profile]+[Path(t['log']) for t in tests['tests'].values()]:
    shutil.copyfile(p,release/p.name)
files=[Path(p) for p in sources]+list(D.glob('*.py'))+list(D.glob('*.ps1'))+list(D.glob('*.sv'))
files+=[O/'build.tcl',O/'simulation_cases.json',O/'ddr_camera_coordqueue.pds',O/'baseline_sources.json']
files+=list(O.glob('tb*.sv'))+list(O.glob('tb*.do'))+list(O.glob('*.hex'))
files+=list((R/'vendor/b/vectors').glob('*.hex'))+list((R/'vendor/b/python').rglob('*.py'))
files+=[R/'pds/program_ddr_camera_coordqueue.tcl',R/'scripts/program_ddr_camera_coordqueue.ps1',R/'下载高清校正_坐标预计算版.cmd',R/'docs/坐标预计算提速_20261013.md']
files+=[Path(p) for p in baseline if Path(p).name=='frame_processor.v']
with zipfile.ZipFile(release/'source_snapshot.zip','x',zipfile.ZIP_DEFLATED) as z:
    for p in dict.fromkeys(files):z.write(p,p.relative_to(R).as_posix())
with zipfile.ZipFile(release/'source_snapshot.zip') as z:assert z.testzip() is None
record={'sealed_at_utc':datetime.now(timezone.utc).isoformat(),'simulations_passed':True,'timing_passed':True,
    'part':'PG2L100H -6 FBG676','top':'video_correct_ddr_top','tests':tests,
    'base_release':'release/ddr_camera_hires_rowtrain_20261013','changed_sources':changed,'unchanged_compiled_source_count':len(unchanged),
    'source_sampling':[960,540],'processed_output':[640,904],'hdmi_output':[1920,1080],'processing_clock_mhz':27,
    'coordinate_lookahead_credits':16,'source_memory_requests_outstanding':1,'sampled_pixels_outstanding':1,
    'modeled_cycle_speed_ratio':comparison['modeled_cycle_speed_ratio'],'baseline_cycles':25094025,'new_cycles':12365414,
    'working_baseline_actual_observed_hz':0.85,'hardware_programmed':False,'hardware_speedup_accepted':False,
    'actual_camera_correction_accepted_for_new_image':False,'thermal_reading_for_new_image_available':False,'flash_modified':False,
    'change':'Only frame processor scheduling: reserve up to16 coordinate credits across pipeline/queue/current pixel, hide coordinate latency behind current source sampling/interpolation, preserve ordered tags and one outstanding source read. Geometry, dimensions, thresholds, clocks, constraints, DDR and display unchanged.',
    'hardware_hold':'User powered board off after reported hot center/heatsink and nearby chips. This build was host-only; next board test requires cooling and a reliable current thermal check.',
    'performance_limit':'Whole-frame synthetic memory test exact RGB passes;2.03x cycle improvement is not a measured new board FPS or maximum throughput.',
    'timing_limit':'All constraints met under existing vendor/provisional external HDMI IO timing models.',
    'files':{p.name:sha(p) for p in release.iterdir() if p.is_file()}}
(release/'build_qualification.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'release':str(release),'sha256':sha(release/bit.name),'changed_sources':len(changed),'unchanged_sources':len(unchanged),'hardware_programmed':False},indent=2))
