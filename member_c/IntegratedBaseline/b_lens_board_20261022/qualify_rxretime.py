"""Qualify external falling capture plus rising retiming against exact artifacts."""
from pathlib import Path
import argparse,hashlib,json,re,shutil
O=Path('D:/FPGA/output/b_lens_board_rxretime_20261023')
P=Path('D:/FPGA/output/b_lens_board_trial_20261022_v5')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def require(ok,message):
 if not ok:raise RuntimeError(message)
def read(p):return p.read_text(encoding='utf-8-sig',errors='replace')
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--implementation',choices=['build','performance'],default='build');implementation=ap.parse_args().implementation
 m=json.loads(read(O/'source_manifest.json'))
 require(m['changed']==['video_correct_ddr_top.v'],'Unexpected scope')
 for n,h in m['candidate_source_sha256'].items():require(sha(O/'sources'/n)==h,'Candidate drift '+n)
 for n,h in m['parent_source_sha256'].items():require(sha(P/'sources'/n)==h,'Parent drift '+n)
 old=read(P/'sources/video_correct_ddr_top.v')
 require(old.count(m['old_frontend'])==1,'Unexpected parent frontend')
 expected=old.replace(m['old_frontend'],m['new_frontend'])
 require(read(O/'sources/video_correct_ddr_top.v')==expected,'Only RX frontend may differ')
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
 phase=Path('D:/FPGA/output/rx_frontend_phase_test_20261023_valid')
 red=read(phase/'red/simulation.log');green=read(phase/'green/simulation.log')
 require('Fatal: RX_CAPTURE_EDGE_OR_ALIGNMENT' in red,'Old capture did not fail the phase model')
 require('PASS RX_FRONTEND_PHASE_ALL27_SIGNALS checks=1998 reset=1' in green and 'Errors: 0, Warnings: 0' in green,'New capture phase model failed')
 phase_binding=json.loads(read(phase/'green/binding.json'))
 require(phase_binding['top_sha256']==sha(O/'sources/video_correct_ddr_top.v'),'Frontend extraction top drift')
 require(phase_binding['extracted_frontend_sha256']==sha(phase/'green/rx_frontend.v'),'Frontend extraction drift')
 records={}
 for suffix in ['input30','input60']:
  d=Path('D:/FPGA/output/b_lens_rxretime_'+suffix+'_20261023')
  log=read(d/'simulation.log');comp=read(d/'compile.log')
  require('PASS RAW_PIPELINE corrected=1 native=1 pixels=14515200 unique_scans=2 published=2' in log,'Missing full regression '+suffix)
  require('Errors: 0, Warnings: 0' in log and 'Errors: 0, Warnings: 0' in comp,'Regression errors '+suffix)
  require(not re.search(r'\*\* (Error|Fatal|Warning):',log+comp),'Regression diagnostic '+suffix)
  binding=json.loads(read(d/'candidate_binding.json'))
  require(binding['top_sha256']==sha(O/'sources/video_correct_ddr_top.v'),'Top test model binding changed')
  require(binding['stimulus_timing']=='External VS/DE/RGB driven1ns after rising edge,captured on falling edge,retimed on rising edge; no same-edge race','Sampling race in stimulus')
  compiled=json.loads(read(d/'compiled_hashes.json'))
  for n,h in compiled.items():
   require(sha(d/'source_snapshot'/n)==h,'Test snapshot drift '+n)
   if n!='tb_lens_board.sv':require(sha(O/'sources'/n)==h,'Test source drift '+n)
  records[suffix]={'compiled_sha256':compiled,'simulation_log_sha256':sha(d/'simulation.log'),'candidate_binding':binding}
 fullsync=Path('D:/FPGA/output/b_lens_rxretime_frontsync_20261023')
 sync_log=read(fullsync/'simulation.log');sync_compile=read(fullsync/'compile.log')
 require('PASS RAW_PIPELINE corrected=1 native=1 pixels=14515200 unique_scans=2 published=2' in sync_log,'Missing actual VS recovery regression')
 require('Errors: 0, Warnings: 0' in sync_log and not re.search(r'\*\* (Error|Fatal|Warning):',sync_log+sync_compile),'VS recovery regression diagnostic')
 raw_log=read(fullsync/'simulation_raw.log')
 require('PASS RAW_PIPELINE corrected=0 native=1 pixels=4147200 unique_scans=2 published=2' in raw_log and 'Errors: 0, Warnings: 0' in raw_log and not re.search(r'\*\* (Error|Fatal|Warning):',raw_log),'RAW frontend regression failed')
 require(json.loads(read(fullsync/'candidate_binding.json'))['top_sha256']==sha(O/'sources/video_correct_ddr_top.v'),'VS recovery top binding drift')
 sync_hashes=json.loads(read(fullsync/'compiled_hashes.json'))
 for n,h in sync_hashes.items():
  require(sha(fullsync/'source_snapshot'/n)==h,'VS recovery test source drift '+n)
  if n!='tb_lens_board.sv':require(sha(O/'sources'/n)==h,'VS recovery production drift '+n)
 records['frontend_and_vs_recovery']={'compiled_sha256':sync_hashes,'simulation_log_sha256':sha(fullsync/'simulation.log'),'raw_log_sha256':sha(fullsync/'simulation_raw.log')}
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
 'native_regressions':records,'fixtures':fixture_record,'implementation':implementation,'implementation_log_sha256':sha(b/'pds_console.log' if implementation=='performance' else O/'pds_console.log'),'interface_audit_sha256':sha(O/'interface_audit.json'),'config_regression_sha256':sha(cfg/'simulation.log'),'frontend_phase_sha256':sha(phase/'green/simulation.log'),'hardware_programmed':False,'real_video_acceptance':False,'scope':'falling-edge capture plus rising-edge retiming; B lens math unchanged'}
 (out/'qualification.json').write_text(json.dumps(q,indent=2)+'\n')
 (out/'program.tcl').write_text('cfg_set_tcl_break -flag true\ncfg_connect -ip 127.0.0.1 -port 65420\ncfg_scan_chain\n'+f'cfg_assign_file -file {{{(out/bit.name).as_posix()}}} -device_index 0\n'+'cfg_set_device_property -device_index 0 -program 1\ncfg_program -device_index 0\ncfg_verify -device_index 0\ncfg_disconnect\ncfg_close\n')
 print('RX_RETIME_CANDIDATE_QUALIFIED',sha(bit))
if __name__=='__main__':main()
