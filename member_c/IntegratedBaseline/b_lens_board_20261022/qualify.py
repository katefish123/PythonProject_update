"""Fail-closed: exact changed-board inputs, native regression and final timing."""
from pathlib import Path
import argparse,hashlib,json,re,shutil
if not __debug__:
 raise RuntimeError('Optimized Python is prohibited: release checks must remain active')
R=Path(__file__).resolve().parent
O=Path('D:/FPGA/output/b_lens_board_trial_20261022_v5')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):
 b=p.read_bytes();return b.decode('utf-16' if b.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8-sig',errors='replace')
def main():
 args=argparse.ArgumentParser()
 args.add_argument('--implementation',default='build',choices=['build','seed73','route91','qualified_iteration1'])
 implementation=args.parse_args().implementation
 m=json.loads((O/'source_manifest.json').read_text());records={}
 for n,h in m['candidate_source_sha256'].items():assert sha(O/'sources'/n)==h,('candidate drift',n)
 for n,h in m['original_inputs_sha256'].items():assert sha(Path('D:/FPGA/output/c_board_next_v5c_20261016/sources')/n)==h,('frozen drift',n)
 for suffix,corr,pixels in [('native_final',1,14515200),('raw_final',0,4147200)]:
  d=Path('D:/FPGA/output/b_lens_board_sim_20261022_'+suffix);log=read(d/'simulation.log');comp=read(d/'compile.log')
  assert 'Errors: 0, Warnings: 0' in log and 'Errors: 0, Warnings: 0' in comp
  assert not re.search(r'\*\* (Error|Fatal|Warning):',log+comp)
  assert f'PASS RAW_PIPELINE corrected={corr} native=1 pixels={pixels} unique_scans=2 published=2' in log
  compiled=json.loads((d/'compiled_hashes.json').read_text(encoding='utf-8-sig'))
  for n,h in compiled.items():
   assert sha(d/'source_snapshot'/n)==h
   assert sha(R/n if n=='tb_lens_board.sv' else O/'sources'/n)==h,(suffix,n)
  records[suffix]={'pixels':pixels,'unique_displayed_frames':2,'compiled_sha256':compiled,'simulation_log_sha256':sha(d/'simulation.log')}
 b=O/implementation
 if implementation=='build':
  log=read(O/'pds_console.log')
  assert 'Action from compile to gen_bit_stream: Total Real Time elapsed is' in log,'PDS full flow incomplete'
 elif implementation=='seed73':
  log=read(b/'project_reroute.log')
  assert 'Process "Place & Route" done.' in log,'New implementation incomplete'
  for phase in ['Compile','Synthesize','Device Map']:
   assert f'Process "{phase}" done.' in log,('incomplete source build',phase)
  meta=json.loads((b/'finish/input_binding.json').read_text())
  assert meta['pnr_sha256']==sha(b/'place_route/video_correct_ddr_top_pnr.adf')
  assert meta['candidate_manifest_sha256']==sha(O/'source_manifest.json')
  assert meta['routed_build_log_sha256']==sha(b/'project_reroute.log')
  finish=read(b/'finish/finish_console.log')
  direct=read(b/'finish/report_direct.log')
  assert meta['timing_exit_code']==0 and meta['timing_log_sha256']==sha(b/'finish/report_direct.log')
  assert meta['timing_project_sha256']==sha(b/'finish/finish.pds')
  assert 'Report timing is finished successfully.' in direct and 'Process "Generate Bitstream" done.' in finish
  log+='\n'+finish+'\n'+direct
  b=b/'finish'
 elif implementation=='route91':
  meta=json.loads((b/'input_binding.json').read_text())
  assert meta['candidate_manifest_sha256']==sha(O/'source_manifest.json')
  assert meta['upstream_build_log_sha256']==sha(O/'seed73/project_reroute.log')
  upstream=read(O/'seed73/project_reroute.log')
  for phase in ['Compile','Synthesize','Device Map','Place & Route']:
   assert f'Process "{phase}" done.' in upstream,('upstream incomplete',phase)
  assert not re.search(r'^E:|ERROR:',upstream,re.M)
  for p,h in meta['inputs_sha256'].items():assert sha(Path(p))==h,('mapped/placed input drift',p)
  log=read(b/'route_console.log')
  for phase in ['Place & Route','Report Timing','Generate Bitstream']:
   assert f'Process "{phase}" done.' in log,('new implementation incomplete',phase)
 else:
  meta=json.loads((b/'input_binding.json').read_text())
  assert meta['candidate_manifest_sha256']==sha(O/'source_manifest.json')
  assert meta['upstream_build_log_sha256']==sha(O/'seed73/project_reroute.log')
  assert meta['route_input_binding_sha256']==sha(O/'route91/input_binding.json')
  upstream=read(O/'seed73/project_reroute.log')
  for phase in ['Compile','Synthesize','Device Map','Place & Route']:
   assert f'Process "{phase}" done.' in upstream
  assert not re.search(r'^E:|ERROR:',upstream,re.M)
  route_binding=json.loads((O/'route91/input_binding.json').read_text())
  for p,h in route_binding['inputs_sha256'].items():assert sha(Path(p))==h
  assert meta['completed_iteration_pnr_sha256']==sha(b/'video_correct_ddr_top_pnr.adf')
  assert meta['completed_iteration_report_sha256']==sha(b/'iteration_report_original.rtr')
  assert meta['final_report_sha256']==sha(b/'video_correct_ddr_top.rtr')
  assert meta['route_log_snapshot_sha256']==sha(b/'route_log_snapshot.log')
  snapshot=read(b/'route_log_snapshot.log')
  assert "Design 'video_correct_ddr_top' has been routed successfully." in snapshot
  assert not re.search(r'^E:|ERROR:',snapshot,re.M)
  direct=read(b/'report_direct.log');log=read(b/'finish_console.log')+'\n'+direct
  assert 'Report timing is finished successfully.' in direct
  assert meta['timing_exit_code']==0 and meta['timing_log_sha256']==sha(b/'report_direct.log')
  assert meta['timing_project_sha256']==sha(b/'finish.pds')
  assert 'Process "Generate Bitstream" done.' in log
 assert not re.search(r'^E:|ERROR:',log,re.M),'PDS error'
 # Iterative routing emits intermediate .rtr files under place_route. Only
 # the separate final Report Timing action may qualify a routed release.
 if implementation=='qualified_iteration1':reports=[b/'video_correct_ddr_top.rtr']
 else:reports=list((b/'report_timing').glob('*.rtr')) if implementation=='route91' else list(b.rglob('*.rtr'))
 assert len(reports)==1,reports
 t=read(reports[0]);assert 'Design Summary : All Constraints Met.' in t,'Final timing not met'
 sections=re.findall(r'(?:Setup|Hold|Recovery|Removal|Minimum Pulse Width) Summary\((?:Slow|Fast) Corner\):\s*\n(.*?)(?=\n\s*\n)',t,re.S)
 rows=[]
 for section in sections:
  count=0
  for line in section.splitlines():
   v=re.search(r'(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*$',line)
   if v:assert float(v[1])>=0 and int(v[3])==0,line;rows.append(line.strip());count+=1
  assert count>0,'empty timing section'
 assert len(sections)==10 and len(rows)==100,(len(sections),len(rows))
 expected=read(Path('D:/FPGA/output/b_lens_board_trial_20261022_v5/build/report_timing/video_correct_ddr_top.rtr'))
 expected_sections=re.findall(r'(?:Setup|Hold|Recovery|Removal|Minimum Pulse Width) Summary\((?:Slow|Fast) Corner\):\s*\n(.*?)(?=\n\s*\n)',expected,re.S)
 def clock_pairs(section):
  return [line[:v.start()].split() for line in section.splitlines()
   if (v:=re.search(r'(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*$',line))]
 assert len(expected_sections)==10
 for actual,reference in zip(sections,expected_sections):
  assert clock_pairs(actual)==clock_pairs(reference),'Missing/reordered clock domain summary'
 bits=list(b.rglob('*.sbit'));masks=list(b.rglob('*.smsk'));assert len(bits)==len(masks)==1
 assert bits[0].stat().st_size>1000000 and masks[0].stat().st_size>0
 out=O/('release' if implementation=='build' else 'release_'+implementation);out.mkdir(exist_ok=True)
 for p in bits+masks:shutil.copyfile(p,out/p.name)
 r={'candidate':'B V2 18mm lens-only native1080p trial','ready_for_authorized_cram_experiment':True,'enterprise_acceptance':False,'optical_acceptance':False,'hardware_programmed':False,
 'implementation':implementation,'build_log_sha256':hashlib.sha256(log.encode()).hexdigest(),
 'native_regressions':records,'timing_qualified':True,'timing_summary_rows':rows,'final_timing_report':str(reports[0]),'final_timing_sha256':sha(reports[0]),
 'bitstream':str(out/bits[0].name),'mask':str(out/masks[0].name),'bitstream_sha256':sha(bits[0]),'mask_sha256':sha(masks[0]),'candidate_source_sha256':m['candidate_source_sha256'],
 'limitations':['lens-only trial; no paper-boundary or outside-paper identity','trial calibration deploy_to_fpga=false retained','synthetic DDR latency is not real PHY acceptance','new-image rate and MTF/SFR not hardware qualified']}
 (out/'qualification.json').write_text(json.dumps(r,indent=2)+'\n')
 (out/'program.tcl').write_text('cfg_set_tcl_break -flag true\ncfg_connect -ip 127.0.0.1 -port 65420\ncfg_scan_chain\n'+f'cfg_assign_file -file {{{(out/bits[0].name).as_posix()}}} -device_index 0\n'+'cfg_set_device_property -device_index 0 -program 1\ncfg_program -device_index 0\ncfg_verify -device_index 0\ncfg_disconnect\ncfg_close\n',encoding='ascii')
 print('QUALIFIED_EXPERIMENT_ONLY final_timing_rows='+str(len(rows))+' bit_sha256='+sha(bits[0]))
if __name__=='__main__':main()
