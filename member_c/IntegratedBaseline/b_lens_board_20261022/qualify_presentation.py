"""Qualify external falling capture plus rising retiming against exact artifacts."""
from pathlib import Path
import argparse,hashlib,json,re,shutil
O=Path('D:/FPGA/output/b_lens_board_presentation3_20261023')
P=Path('D:/FPGA/output/b_lens_board_trial_20261022_v5')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def require(ok,message):
 if not ok:raise RuntimeError(message)
def read(p):return p.read_text(encoding='utf-8-sig',errors='replace')
def main():
 global O
 ap=argparse.ArgumentParser();ap.add_argument('--implementation',choices=['build','performance'],default='build');ap.add_argument('--candidate',type=Path,default=O);args=ap.parse_args();implementation=args.implementation;O=args.candidate.resolve()
 m=json.loads(read(O/'source_manifest.json'))
 repair=m.get('status_rom_repair')
 require(m['changed']==['video_correct_ddr_top.v','continuous_source_path.v']+(['status_overlay.v'] if repair else []),'Unexpected scope')
 rom_record=None
 if repair:
  origin=Path(repair['parent']);oq=json.loads(read(origin/'release/qualification.json'))
  require(sha(origin/'release/qualification.json')==repair['parent_qualification_sha256'] and oq['timing_qualified'],'Status parent qualification drift')
  for n,h in oq['candidate_source_sha256'].items():
   require(sha(origin/'sources'/n)==h,'Status parent source drift '+n)
   if n!='status_overlay.v':require(sha(O/'sources'/n)==h,'Only status glyph ROM may differ from qualified parent '+n)
  original=read(origin/'sources/status_overlay.v');current=read(O/'sources/status_overlay.v')
  pattern=re.compile(r"^9'h([0-9a-f]+): bits=160'h([0-9a-f]+);$",re.M)
  matches=list(pattern.finditer(original));last={v[1]:v.start() for v in matches}
  exact=pattern.sub(lambda v:v[0] if last[v[1]]==v.start() else '',original)
  require(current==exact,'Unexpected status ROM logic change')
  rows=pattern.findall(current);require(len(rows)==len(dict(rows)) and len(matches)-len(rows)==48,'Status glyph address regression')
  require(sha(origin/'sources/status_overlay.v')==repair['old_sha256'] and sha(O/'sources/status_overlay.v')==repair['new_sha256'],'Status RTL binding drift')
  rg=Path(repair['green_test']);rr=Path(repair['red_test'])
  require(sha(rg/'status_overlay.v')==repair['new_sha256'] and sha(rr/'status_overlay.v')==repair['old_sha256'],'Status tested source drift')
  require(sha(rg/'tb.sv')==sha(rr/'tb.sv'),'Status red/green testbench differs')
  require('Fatal: WRONG_STATUS_GLYPH' in read(rr/'simulation.log'),'Missing status failing regression')
  require('PASS STATUS_ROM all 80 replacement glyph rows selected' in read(rg/'simulation.log') and 'Errors: 0, Warnings: 0' in read(rg/'simulation.log'),'Missing status passing regression')
  rom_record={'old_sha256':repair['old_sha256'],'new_sha256':repair['new_sha256'],'green_log_sha256':sha(rg/'simulation.log'),'red_log_sha256':sha(rr/'simulation.log'),'testbench_sha256':sha(rg/'tb.sv'),'white_gray_pixels_resolved':False}
 for n,h in m['candidate_source_sha256'].items():require(sha(O/'sources'/n)==h,'Candidate drift '+n)
 for n,h in m['parent_source_sha256'].items():require(sha(P/'sources'/n)==h,'Parent drift '+n)
 old=read(P/'sources/video_correct_ddr_top.v')
 require(old.count(m['old_frontend'])==1,'Unexpected parent frontend')
 expected=old.replace(m['old_frontend'],m['new_frontend'])
 counter=m['physical_counter_frontend']
 require(expected.count(counter['old'])==1,'Physical counter parent changed')
 expected=expected.replace(counter['old'],counter['new'])
 presentation=m['presentation']
 parent=Path(presentation['qualified_parent'])
 require(sha(parent/'sources/video_correct_ddr_top.v')==presentation['qualified_parent_top_sha256'],'Presentation parent drift')
 require(read(parent/'sources/video_correct_ddr_top.v')==expected,'Unexpected qualified presentation parent')
 for field in ['header','overlay','status']:
  require(expected.count(presentation['old_'+field])==1,'Unexpected presentation block '+field)
  expected=expected.replace(presentation['old_'+field],presentation['new_'+field])
 require(read(O/'sources/video_correct_ddr_top.v')==expected,'Only exact presentation delta may differ')
 bypass=m['metadata_bypass']
 parent_path=P/'sources/continuous_source_path.v'
 require(sha(parent_path)==bypass['parent_source_sha256'],'Metadata parent drift')
 text=read(parent_path)
 require(text.count(bypass['old'])==1,'Unexpected metadata block')
 require(read(O/'sources/continuous_source_path.v')==text.replace(bypass['old'],bypass['new']),'Only unused metadata branch may differ')
 fixtures=Path('D:/FPGA/output/b_lens_board_fixtures_20261022')
 fixture_record=json.loads(read(fixtures/'manifest.json'))
 for n,h in fixture_record['fixtures_sha256'].items():require(sha(fixtures/n)==h,'Golden fixture drift '+n)
 b_original=Path('D:/FPGA/team_downloads/20261022_B_lens_v2/member_b_lens_pipeline_v2')
 for n,h in fixture_record['source_sha256'].items():require(sha(b_original/n)==h,'B reference drift '+n)
 audit=json.loads(read(O/'interface_audit.json'))
 require(audit['all_pass'] and audit['physical_port_bits']==144 and audit['pds_source_count']==147,'Interface audit incomplete')
 require(audit['top_sha256']==sha(O/'sources/video_correct_ddr_top.v'),'Audit binding drift')
 require(audit['pds_build_tcl_sha256']==sha(O/'build.tcl'),'Build definition changed after audit')
 for path,h in audit['pds_input_sha256'].items():require(sha(Path(path))==h,'PDS input drift '+path)
 project_inputs=[(O/'build'/p).resolve() for p in re.findall(r'_file "(\.\./sources/[^"]+)"',read(O/'build/build.pds'))]
 require(project_inputs==[Path(p) for p in audit['pds_input_sha256']],'Actual PDS project changed after audit')
 cfg=Path('D:/FPGA/output/b_lens_rxretime_config_clean_20261023')
 cfglog=read(cfg/'simulation.log');cfgcomp=read(cfg/'compile.log')
 for token in ['TEST_PASS_CONFIG','TEST_PASS_OPEN_DRAIN','TEST_PASS_BOOTSTRAP_NACK_RECOVERY','TEST_PASS_POSTPROBE_NACK_FATAL','TEST_PASS_NO_DEVICE']:
  require(token in cfglog,'Missing configuration regression '+token)
 require('Errors: 0, Warnings: 0' in cfglog and not re.search(r'\*\* (Error|Fatal|Warning):|TEST_FAIL',cfglog+cfgcomp),'Configuration regression diagnostic')
 cfgbinding=json.loads(read(cfg/'source_binding.json'))
 for n,h in cfgbinding.items():require(sha(O/'sources'/n)==h,'Configuration source binding drift '+n)
 phase=Path('D:/FPGA/output/rx_frontend_phase_test_20261023_release2')
 red=read(phase/'red/simulation.log');green=read(phase/'green/simulation.log')
 require('Fatal: RX_CAPTURE_EDGE_OR_ALIGNMENT' in red,'Old capture did not fail the phase model')
 require('PASS RX_FRONTEND_PHASE_ALL27_SIGNALS checks=1998 reset=1' in green and 'Errors: 0, Warnings: 0' in green,'New capture phase model failed')
 phase_binding=json.loads(read(phase/'green/binding.json'))
 require(phase_binding['top_sha256']==presentation['qualified_parent_top_sha256'],'Frontend extraction top drift')
 require(phase_binding['extracted_frontend_sha256']==sha(phase/'green/rx_frontend.v'),'Frontend extraction drift')
 telemetry=Path('D:/FPGA/output/lens_telemetry_phase_20261023')
 require('Fatal: PHYSICAL_INPUT_COUNT' in read(telemetry/'red/simulation.log'),'Old telemetry did not expose phase defect')
 tl=read(telemetry/'green/simulation.log')
 require('PASS PHYSICAL_TELEMETRY_PHASE clock_stall=1 reset=1' in tl and 'Errors: 0, Warnings: 0' in tl,'Physical telemetry regression failed')
 tb=json.loads(read(telemetry/'green/binding.json'))
 require(tb['top_sha256']==presentation['qualified_parent_top_sha256'] and tb['extracted_sha256']==sha(telemetry/'green/telemetry.v'),'Physical telemetry binding drift')
 records={'physical_telemetry':{'simulation_log_sha256':sha(telemetry/'green/simulation.log'),'binding':tb}}
 if rom_record:records['status_rom_repair']=rom_record
 for suffix in ['input30','input60']:
  d=Path('D:/FPGA/output/b_lens_release2_'+suffix+'_20261023')
  log=read(d/'simulation.log');comp=read(d/'compile.log')
  require('PASS RAW_PIPELINE corrected=1 native=1 pixels=14515200 unique_scans=2 published=2' in log,'Missing full regression '+suffix)
  require('Errors: 0, Warnings: 0' in log and 'Errors: 0, Warnings: 0' in comp,'Regression errors '+suffix)
  require(not re.search(r'\*\* (Error|Fatal|Warning):',log+comp),'Regression diagnostic '+suffix)
  binding=json.loads(read(d/'candidate_binding.json'))
  require(binding['top_sha256']==presentation['qualified_parent_top_sha256'],'Top test model binding changed')
  require(binding['stimulus_timing']=='External VS/DE/RGB driven1ns after rising edge,captured on falling edge,retimed on rising edge; no same-edge race','Sampling race in stimulus')
  compiled=json.loads(read(d/'compiled_hashes.json'))
  for n,h in compiled.items():
   require(sha(d/'source_snapshot'/n)==h,'Test snapshot drift '+n)
   if n!='tb_lens_board.sv':require(sha(O/'sources'/n)==h,'Test source drift '+n)
  records[suffix]={'compiled_sha256':compiled,'simulation_log_sha256':sha(d/'simulation.log'),'candidate_binding':binding}
 fullsync=Path('D:/FPGA/output/b_lens_release2_frontsync_20261023')
 sync_log=read(fullsync/'simulation.log');sync_compile=read(fullsync/'compile.log')
 require('PASS RAW_PIPELINE corrected=1 native=1 pixels=14515200 unique_scans=2 published=2' in sync_log,'Missing actual VS recovery regression')
 require('Errors: 0, Warnings: 0' in sync_log and not re.search(r'\*\* (Error|Fatal|Warning):',sync_log+sync_compile),'VS recovery regression diagnostic')
 raw_log=read(fullsync/'simulation_raw.log')
 require('PASS RAW_PIPELINE corrected=0 native=1 pixels=4147200 unique_scans=2 published=2' in raw_log and 'Errors: 0, Warnings: 0' in raw_log and not re.search(r'\*\* (Error|Fatal|Warning):',raw_log),'RAW frontend regression failed')
 require(json.loads(read(fullsync/'candidate_binding.json'))['top_sha256']==presentation['qualified_parent_top_sha256'],'VS recovery top binding drift')
 sync_hashes=json.loads(read(fullsync/'compiled_hashes.json'))
 for n,h in sync_hashes.items():
  require(sha(fullsync/'source_snapshot'/n)==h,'VS recovery test source drift '+n)
  if n!='tb_lens_board.sv':require(sha(O/'sources'/n)==h,'VS recovery production drift '+n)
 records['frontend_and_vs_recovery']={'compiled_sha256':sync_hashes,'simulation_log_sha256':sha(fullsync/'simulation.log'),'raw_log_sha256':sha(fullsync/'simulation_raw.log')}
 ownership=Path('D:/FPGA/output/b_lens_release2_ownership_20261023')
 ownlog=read(ownership/'simulation.log');owncompile=read(ownership/'compile.log')
 for token in ['PASS consecutive continuous source','PASS invalid extraheight/shortwidth/shortheight','PASS FIFO-full terminal retention','PASS RX clock stall/restart','PASS stale release rejected','PASS shared hard reset','PASS continuous capture complete test suite']:
  require(token in ownlog,'Missing ownership protection '+token)
 require('Errors: 0, Warnings: 0' in ownlog and 'Errors: 0, Warnings: 0' in owncompile and not re.search(r'\*\* (Error|Fatal|Warning):',ownlog+owncompile),'Ownership regression diagnostic')
 ownhash=json.loads(read(ownership/'compiled_hashes.json'))
 for n,h in ownhash.items():
  require(sha(ownership/'source_snapshot'/n)==h,'Ownership test drift '+n)
  if n!='tb_continuous_source.sv':require(sha(O/'sources'/n)==h,'Ownership production drift '+n)
 records['ownership_and_invalid_input']={'compiled_sha256':ownhash,'simulation_log_sha256':sha(ownership/'simulation.log')}
 display=Path('D:/FPGA/output/presentation_green3_20261023')
 dlog=read(display/'simulation.log');dcomp=read(display/'compile.log')
 require('PASS PRESENTATION' in dlog and 'Errors: 0, Warnings: 0' in dlog and not re.search(r'\*\* (Error|Fatal|Warning):',dlog+dcomp),'Presentation regression failed')
 dbinding=json.loads(read(display/'binding.json'))
 require(dbinding['top_sha256']==sha(O/'sources/video_correct_ddr_top.v'),'Presentation top drift')
 require(dbinding['extracted_sha256']==sha(display/'presentation_policy.v') and presentation['new_overlay'] in read(display/'presentation_policy.v'),'Presentation extraction drift')
 require(dbinding['bench_sha256']==sha(display/'tb.sv') and 'LONG_STALE_FRAME_HIDDEN' in read(display/'tb.sv'),'Missing long-stale test')
 require('Fatal: CLEAN_FULLHD_IMAGE_OBSCURED' in read(Path('D:/FPGA/output/presentation_red_20261023/simulation.log')),'Old HUD did not fail')
 require('Fatal: LONG_STALE_FRAME_HIDDEN' in read(Path('D:/FPGA/output/presentation_stale_red_20261023/simulation.log')),'Hidden long-stale variant did not fail')
 records['presentation']={'simulation_log_sha256':sha(display/'simulation.log'),'binding':dbinding,'scope':'Clean mode,debounced key chord,frame-boundary updates,visible faults and long-stale warning; no datapath change'}
 continuous=Path('D:/FPGA/output/b_lens_submission_continuous6_20261023')
 cb=json.loads(read(continuous/'verification.json'))
 require(cb['checked_pixels']==64281600 and len(set(cb['distinct_source_patterns_sha256_uint32le'].values()))==6,'Six distinct fullHD frames missing')
 require(cb['simulation_sha256']==sha(continuous/'simulation.log') and cb['compile_sha256']==sha(continuous/'compile.log'),'Continuous regression log drift')
 require('pixels=64281600 unique_scans=6 published=6' in re.sub(r'\s+',' ',read(continuous/'simulation.log')),'Continuous regression failed')
 for n,h in cb['production_sha256'].items():require(sha(O/'sources'/n)==h and sha(continuous/'source_snapshot'/n)==h,'Continuous source drift '+n)
 require(sha(continuous/'source_snapshot/tb_lens_board.sv')==cb['testbench_sha256'],'Continuous testbench drift')
 records['continuous6']={'verification_sha256':sha(continuous/'verification.json'),'simulation_log_sha256':sha(continuous/'simulation.log'),'reused_unchanged_datapath':True}
 b=O/implementation
 if implementation=='performance':
  route_binding=json.loads(read(b/'input_binding.json'))
  require(route_binding['candidate_manifest_sha256']==sha(O/'source_manifest.json'),'Route source manifest drift')
  require(route_binding['upstream_build_tcl_sha256']==sha(O/'build.tcl'),'Route upstream build drift')
  require(route_binding['route_tcl_sha256']==sha(b/'route.tcl'),'Route Tcl drift')
  for path,entry in route_binding['inputs'].items():
   require(sha(Path(path))==entry['sha256'] and sha(Path(entry['upstream']))==entry['sha256'],'Route mapped/placed input drift '+path)
  upstream_log=read(O/'pds_console.log')
  for name in ['Compile','Synthesize','Device Map','Place & Route']:require(f'Process "{name}" done.' in upstream_log,'Incomplete route parent '+name)
  require(not re.search(r'^E:|ERROR:',upstream_log,re.M),'Upstream build error')
  actual_project=read(b/'performance.pds')
  actual_inputs=[(b/p).resolve() for p in re.findall(r'_file "(\.\./sources/[^"]+)"',actual_project)]
  require(actual_inputs==[Path(p) for p in audit['pds_input_sha256']],'Performance project source drift')
  log=read(b/'pds_console.log')
 else:log=read(O/'pds_console.log')
 require('Process "Generate Bitstream" done.' in log and not re.search(r'^E:|ERROR:',log,re.M),'PDS incomplete/error')
 reports=list((b/'report_timing').glob('*.rtr'));require(len(reports)==1,'Missing final timing report')
 t=read(reports[0]);require('Design Summary : All Constraints Met.' in t,'Final timing not met')
 pattern=r'(?:Setup|Hold|Recovery|Removal|Minimum Pulse Width) Summary\((?:Slow|Fast) Corner\):\s*\n(.*?)(?=\n\s*\n)'
 sections=re.findall(pattern,t,re.S);ref=re.findall(pattern,read(P/'qualified_iteration1/video_correct_ddr_top.rtr'),re.S)
 def rows(section):
  return [(line,v) for line in section.splitlines() if (v:=re.search(r'(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*$',line))]
 require(len(sections)==len(ref)==10,'Missing timing section')
 summary=[]
 for actual,reference in zip(sections,ref):
  ar,rr=rows(actual),rows(reference)
  require([s[:v.start()].split() for s,v in ar]==[s[:v.start()].split() for s,v in rr],'Missing clock domain')
  for s,v in ar:require(float(v[1])>=0 and int(v[3])==0,'Failed timing '+s);summary.append(s.strip())
 require(len(summary)==100,'Incomplete 100-row summary')
 bit=b/'generate_bitstream/video_correct_ddr_top.sbit';mask=bit.with_suffix('.smsk')
 require(bit.stat().st_size>1000000 and mask.stat().st_size>0,'Missing bit/mask')
 out=O/'release';require(not out.exists(),'Preserve existing release');out.mkdir()
 for p in [bit,mask]:shutil.copyfile(p,out/p.name)
 q={'ready_for_authorized_cram_experiment':True,'timing_qualified':True,'candidate_source_sha256':m['candidate_source_sha256'],
 'bitstream':str(out/bit.name),'mask':str(out/mask.name),'bitstream_sha256':sha(bit),'mask_sha256':sha(mask),
 'final_timing_report':str(reports[0]),'final_timing_sha256':sha(reports[0]),'timing_summary_rows':summary,
 'native_regressions':records,'fixtures':fixture_record,'implementation':implementation,'implementation_log_sha256':sha(b/'pds_console.log' if implementation=='performance' else O/'pds_console.log'),'interface_audit_sha256':sha(O/'interface_audit.json'),'config_regression_sha256':sha(cfg/'simulation.log'),'frontend_phase_sha256':sha(phase/'green/simulation.log'),'hardware_programmed':False,'real_video_acceptance':False,'scope':'Native fullHD lens trial with clean display,diagnostic toggle and stale warning; B/datapath unchanged; original functional regressions reused only for byte-identical modules; real calibration/hardware acceptance pending'}
 if rom_record:
  q['scope']+='; duplicate status glyph precedence corrected; white/gray physical pixel problem unresolved'
  q['white_gray_hardware_problem_resolved']=False
 (out/'qualification.json').write_text(json.dumps(q,indent=2)+'\n')
 (out/'program.tcl').write_text('cfg_set_tcl_break -flag true\ncfg_connect -ip 127.0.0.1 -port 65420\ncfg_scan_chain\n'+f'cfg_assign_file -file {{{(out/bit.name).as_posix()}}} -device_index 0\n'+'cfg_set_device_property -device_index 0 -program 1\ncfg_program -device_index 0\ncfg_verify -device_index 0\ncfg_disconnect\ncfg_close\n')
 print('LENS_RELEASE_CANDIDATE_QUALIFIED',sha(bit))
if __name__=='__main__':main()
