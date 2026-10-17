"""Archive the verified BRAM bring-up bitstream and evidence before pausing."""
from pathlib import Path
import hashlib,json,re,shutil,subprocess,datetime
R=Path(__file__).resolve().parents[1]
build=R/'results/board_bram_final'
timing=(build/'report_timing/video_correct_board_top.rtr').read_text(errors='replace')
if 'Design Summary : All Constraints Met.' not in timing:
    raise RuntimeError('Final timing result is not passing')
log=(R/'results/build_board_final.log').read_text(errors='replace')
if 'Executing : gen_bit_stream successfully.' not in log:
    raise RuntimeError('Final bitstream generation is incomplete')
release=R/'release/bram_bringup_20261009';release.mkdir(parents=True,exist_ok=True)
files=[]
for name in ['video_correct_board_top.sbit','video_correct_board_top.smsk']:
    source=build/'generate_bitstream'/name
    if source.stat().st_size!=3791112:raise RuntimeError('Unexpected programming-file size')
    target=release/name;shutil.copyfile(source,target)
    files.append({'path':str(target.relative_to(R)),'bytes':target.stat().st_size,
                  'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
for source in [build/'report_timing/video_correct_board_top.rtr',
               build/'device_map/video_correct_board_top.dmr',R/'constr/board_bram.fdc']:
    shutil.copyfile(source,release/source.name)
checks=[]
original=json.loads((R/'docs/source_manifest.json').read_text(encoding='utf-8'))
for item in original:
    p=Path(item['source'])
    # Updating C was explicitly requested. The old snapshot remains archived.
    if 'PythonProject_update_C' in str(p):continue
    if p.is_file():
        actual=hashlib.sha256(p.read_bytes()).hexdigest()
        if actual!=item['sha256']:raise RuntimeError(f'Original changed: {p}')
        checks.append({'source':str(p),'sha256':actual,'unchanged':True})
c=Path(r'C:\D\FPGA\PythonProject_update_C')
if subprocess.check_output(['git','status','--porcelain'],cwd=c).strip():
    raise RuntimeError('C checkout has local changes')
sources=[]
for raw in (R/'pds/build_board_bram.tcl').read_text().splitlines():
    m=re.fullmatch(r'add_design \{(.+)\}',raw)
    if m:
        p=Path(m.group(1));sources.append({'path':str(p.relative_to(R)),
                           'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
evidence=[('results/b_native/verification.json','"status": "pass"'),
 ('results/integration/simulation.log','FRAME_PROCESSOR_PASS'),
 ('results/video_tests/simulation_snapshot.log','SNAPSHOT_SHORT_FRAME_REJECT_PASS'),
 ('results/video_tests/simulation_display.log','RESULT_DISPLAY_FRAME_ATOMIC_PASS'),
 ('results/core_tests/simulation.log','VIDEO_CORRECT_CORE_PASS'),
 ('results/board_fixture/simulation/simulation.log','BOARD_FRAME_PASS checked_pixels=36160'),
 ('results/hdmi_config.log','TEST_PASS_NO_DEVICE')]
tests=[]
for rel,marker in evidence:
    p=R/rel
    if marker not in p.read_text(errors='replace'):raise RuntimeError(f'Missing test evidence: {rel}')
    tests.append({'log':rel,'status':'pass','sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
summary={'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'client_date':'2026-10-09','status':'current_stage_verified_paused_at_user_request',
 'c_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=c,text=True).strip(),
 'board':'MES2L676-100HP','part':'PG2L100H-6 FBG676',
 'source_hdmi':[1920,1080],'source_snapshot':[320,180],'result':[160,226],
 'output_hdmi':'1920x1080 @ 60 nominal, 148.5 MHz',
 'hardware_tested':False,'ddr_connected_to_top':False,
 'timing':'All Constraints Met under current provisional IO model',
 'pixel_setup_slack_ns':2.350,
 'resources':{'lut':6740,'ff':8291,'drm_used':145,'drm_total':155,'apm':53,'io':71},
 'bitstream_files':files,'compiled_sources':sources,'tests':tests,
 'originals_verified':checks,
 'next':['USB/JTAG bring-up and HDMI end-to-end physical test',
         'Implement DDR transaction/cache/capture/display adapters and integrate generated IP',
         'Verify DDR calibration, full-resolution geometry and actual throughput']}
(release/'manifest.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
(R/'docs/current_stage_verification.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
print(f'Archived {len(sources)} source hashes, {len(tests)} evidence records, {len(checks)} unchanged original files')
print(json.dumps(files,ensure_ascii=False))
