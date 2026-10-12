"""Archive only a DDR build that passed final timing and bitstream generation."""
from pathlib import Path
import re,json,hashlib,shutil,subprocess,datetime
R=Path(__file__).resolve().parents[1]
B=R/'results/board_ddr_ready'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def logtext(p):
    raw=p.read_bytes()
    return raw.decode('utf-16') if raw.startswith((b'\xff\xfe',b'\xfe\xff')) else raw.decode('utf-8-sig',errors='replace')
timing=B/'report_timing/video_correct_ddr_top.rtr'
t=timing.read_text(errors='replace')
if 'Design Summary : All Constraints Met.' not in t or 'Design Summary : Some Constraints Violated.' in t:
    raise RuntimeError('Final DDR timing is not passing; do not release')
buildlog=R/'results/build_ddr_ready.log'
if 'Executing : gen_bit_stream successfully.' not in buildlog.read_text(errors='replace'):
    raise RuntimeError('Final DDR bitstream has not been generated')
ip=(R/'rtl/memory/ddr3_ip/ddr3_ip.v').read_text(errors='replace')
if not re.search(r'DDRC_TFAW\s*=\s*26\s*;',ip):raise RuntimeError('DDR tFAW must be 26 CK')
evidence={
 'results/ddr_memory/tb_ddr_word_engine.log':'DDR_WORD_ENGINE_PASS',
 'results/ddr_memory/tb_ddr_pixel_cache.log':'DDR_PIXEL_CACHE_PASS',
 'results/ddr_memory/tb_ddr_helpers.log':'DDR_HELPERS_PASS',
 'results/ddr_capture_tests/simulation.log':'DDR_CAPTURE_PASS',
 'results/ddr_core_e2e/simulation.log':'DDR_CORE_PASS',
 'results/ddr_fixture/tb_ddr_full_frame.log':'DDR_FULL_FRAME_TEST_PASSED=1',
 'results/ddr_display/simulation.log':'DDR_DISPLAY_PASS'}
tests=[]
for path,marker in evidence.items():
    p=R/path
    if not p.exists():raise RuntimeError(f'Missing test log: {path}')
    if marker not in logtext(p):raise RuntimeError(f'Missing pass evidence: {path}')
    tests.append({'path':path,'sha256':sha(p),'status':'pass'})
sources=[]
for line in (R/'pds/build_board_ddr.tcl').read_text().splitlines():
    m=re.fullmatch(r'add_design \{(.+)\}',line)
    if m:
        p=Path(m[1]);sources.append({'path':str(p.relative_to(R)),'sha256':sha(p)})
out=R/'release/ddr_integrated_20261009';out.mkdir(parents=True,exist_ok=True)
files=[]
for name in ['video_correct_ddr_top.sbit','video_correct_ddr_top.smsk']:
    p=B/'generate_bitstream'/name
    if p.stat().st_size!=3791112:raise RuntimeError('Unexpected programming-file size')
    dest=out/name;shutil.copyfile(p,dest)
    files.append({'path':str(dest.relative_to(R)),'sha256':sha(dest),'bytes':dest.stat().st_size})
for p in [timing,B/'device_map/video_correct_ddr_top.dmr',R/'constr/board_ddr.fdc',R/'docs/DDR工程说明.md']:
    shutil.copyfile(p,out/p.name)
summary={'client_date':'2026-10-09','utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'status':'DDR_software_build_and_functional_simulation_verified_hardware_pending',
 'part':'PG2L100H -6 FBG676','source_input':[1920,1080],'source_frame':[640,480],'result_frame':[320,452],
 'display':'1920x1080 nominal 60 Hz','memory':'two x16 DDR3 / 32-bit bus / 1000 MT/s / 125 MHz UI',
 'ddr_address_unit':'32-bit word; 256-bit beats advance 8 addresses','tFAW_CK':26,
 'timing_status':'All Constraints Met under vendor PHY and provisional HDMI IO models',
 'hardware_tested':False,'bitstreams':files,'sources':sources,'test_evidence':tests,
 'c_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=Path(r'C:\D\FPGA\PythonProject_update_C'),text=True).strip(),
 'next':'Connect powered board with USB/JTAG, perform DDR calibration/BIST and actual HDMI end-to-end verification'}
(out/'manifest.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
(R/'docs/ddr_stage_verification.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
print(f'DDR release archived: {len(sources)} sources, {len(tests)} evidence logs')
print(json.dumps(files,ensure_ascii=False))
