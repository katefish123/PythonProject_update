"""Archive completed tests only; reject drift from compiled source snapshots."""
from pathlib import Path
import hashlib,json,re,shutil
here=Path(__file__).resolve().parent
out=here/'evidence';out.mkdir(exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):
 b=p.read_bytes();return b.decode('utf-16' if b.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8-sig')
tests={
 'raw_native':'c_board_next_raw_20261016_final_raw_native',
 'corrected_native':'c_board_next_raw_20261016_final_corrected_native',
 'raw_reduced':'c_board_next_raw_20261016_reduced2',
 'corrected_reduced':'c_board_next_raw_20261016_corrected_reduced2',
 'display_small':'c_board_next_display_20261016_single_ack',
 'display_late':'c_board_next_display_20261016_single_ack_late',
 'geometry_units':'c_color_geometry_20261016_root_units',
 'geometry_cdc':'c_color_geometry_20261016_root_cdc',
 'geometry_h':'c_color_geometry_20261016_root_h',
 'geometry_images':'c_color_geometry_20261016_root_images',
 'manager_raw':'c_manager_raw_20261016_green',
 'control':'c_board_next_control_20261016_guard_green',
}
summary={'status':'application simulation milestone; board integration incomplete',
 'physical_timing_qualified':False,'hardware_accepted':False,'new_bitstream_created':False,
 'raw_unique_frame_60fps_achieved':False,'tests':{},
 'upstream_heads_checked':{'main-A':'256b5ea2b8bf4a559f19adfca7465161654b8226','main-B':'4106f3babb65096927d365bbab55f070b90325e2'}}
for name,folder in tests.items():
 src=Path('D:/FPGA/output')/folder;dst=out/name;dst.mkdir(exist_ok=True)
 logs=list(src.glob('*.log'));passes=[]
 for p in logs:
  text=read(p)
  assert not re.search(r'\*\* (Fatal|Error|Warning):',text),(name,p.name)
  shutil.copyfile(p,dst/p.name)
  # ModelSim can wrap printed result lines. Keep full raw logs as evidence.
  passes += re.findall(r'PASS [^\r\n]+',text)
 assert passes,(name,'missing PASS')
 record={'output_directory':str(src),'passes':passes,'logs_sha256':{p.name:sha(p) for p in logs}}
 if name in ['raw_native','corrected_native']:
  manifest=json.loads((here/'integration/source_manifest.json').read_text())
  compiled={p.name:sha(p) for p in (src/'source_snapshot').glob('*')}
  for file,expected in manifest['sources'].items():
   p=Path(file);assert sha(p)==expected==compiled[p.name],('source drift',file)
  assert sha(here/'integration/tb_raw_pipeline.sv')==compiled['tb_raw_pipeline.sv']
  record['compiled_source_sha256']=compiled
  log=read(src/'simulation.log')
  times=[int(t) for t in re.findall(r'PIPELINE_PUBLICATION.*?time=(\d+)',log)]
  record['publication_time_ps']=times
  record['publication_intervals_ns']=[(b-a)/1000 for a,b in zip(times,times[1:])]
  if name=='raw_native':
   intervals=record['publication_intervals_ns'][-3:]
   record['steady_new_images_per_second']=len(intervals)*1e9/sum(intervals)
   record['checked_hdmi_pixels']=22809600
  else: record['checked_hdmi_pixels']=4147200
 summary['tests'][name]=record
for name,folder,pattern in [
 ('manager_expected_red','c_manager_raw_20261016_red','RAW_MUST_PUBLISH_WITHOUT_GEOMETRY'),
 ('ownership_guard_expected_red','c_board_next_control_20261016_guard_red','LOCKED_RAW_BANK_LAUNCHED_CORRECTION')]:
 src=Path('D:/FPGA/output')/folder;dst=out/name;dst.mkdir(exist_ok=True)
 log=src/('simulation.log' if name.startswith('manager') else 'tb_frame_modes.log')
 assert pattern in read(log)
 for p in [src/'compile.log',log]:shutil.copyfile(p,dst/p.name)
 summary['tests'][name]={'expected_failure':pattern,'is_green_qualification':False}
diag=json.loads((here/'diagnostics/evidence/summary.json').read_text())
summary['diagnostics_existing_unit_evidence']=diag
bit=here.parent/'stream_video_20261015/release_candidate_v4s/video_correct_ddr_top.sbit'
assert sha(bit)=='3e3475d30e6fa2488a57a084aa236353077b91d80969b7d1c412c89c064d1b50'
summary['frozen_v4s_sbit_unchanged_sha256']=sha(bit)
summary['remaining']=['RAW throughput about20 new images/s, not60',
 'Board top mode/status/point/H diagnostic wiring',
 'Full-system memory recovery injection and real PHY fault root cause',
 'PDS implementation/timing of new candidate',
 'Camera geometry, optical clarity, long-running motion acceptance']
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print('PASS evidence:',len(tests),'green test groups; two expected-red regressions; exact native sources and frozen sbit verified')
