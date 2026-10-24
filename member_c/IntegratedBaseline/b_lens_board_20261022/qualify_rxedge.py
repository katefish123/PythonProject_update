"""Qualify the single-edge change against source, regressions and final PDS."""
from pathlib import Path
import hashlib,json,re,shutil
O=Path('D:/FPGA/output/b_lens_board_rxedge_20261023')
P=Path('D:/FPGA/output/b_lens_board_trial_20261022_v5')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def require(ok,message):
 if not ok:raise RuntimeError(message)
def read(p):return p.read_text(encoding='utf-8-sig',errors='replace')
def main():
 m=json.loads(read(O/'source_manifest.json'))
 require(m['changed']==['video_correct_ddr_top.v'],'Unexpected scope')
 for n,h in m['candidate_source_sha256'].items():require(sha(O/'sources'/n)==h,'Candidate drift '+n)
 for n,h in m['parent_source_sha256'].items():require(sha(P/'sources'/n)==h,'Parent drift '+n)
 old=read(P/'sources/video_correct_ddr_top.v')
 expected=old.replace('always @(posedge hd_rx_pclk or negedge rx_rst)begin','always @(negedge hd_rx_pclk or negedge rx_rst)begin')
 require(read(O/'sources/video_correct_ddr_top.v')==expected,'Only RX capture edge may differ')
 records={}
 for suffix in ['input30','input60']:
  d=Path('D:/FPGA/output/b_lens_rxedge_'+suffix+'_20261023_phase_clean')
  log=read(d/'simulation.log');comp=read(d/'compile.log')
  require('PASS RAW_PIPELINE corrected=1 native=1 pixels=14515200 unique_scans=2 published=2' in log,'Missing full regression '+suffix)
  require('Errors: 0, Warnings: 0' in log and 'Errors: 0, Warnings: 0' in comp,'Regression errors '+suffix)
  require(not re.search(r'\*\* (Error|Fatal|Warning):',log+comp),'Regression diagnostic '+suffix)
  binding=json.loads(read(d/'candidate_binding.json'))
  require(binding['top_sha256']==sha(O/'sources/video_correct_ddr_top.v'),'Top test model binding changed')
  require(binding['stimulus_timing']=='External VS/DE/RGB driven1ns after rising edge,captured on falling edge; no same-edge race','Sampling race in stimulus')
  compiled=json.loads(read(d/'compiled_hashes.json'))
  for n,h in compiled.items():
   require(sha(d/'source_snapshot'/n)==h,'Test snapshot drift '+n)
   if n!='tb_lens_board.sv':require(sha(O/'sources'/n)==h,'Test source drift '+n)
  records[suffix]={'compiled_sha256':compiled,'simulation_log_sha256':sha(d/'simulation.log'),'candidate_binding':binding}
 b=O/'build';log=read(O/'pds_console.log')
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
 out=O/'release';out.mkdir(exist_ok=True)
 for p in [bit,mask]:shutil.copyfile(p,out/p.name)
 q={'ready_for_authorized_cram_experiment':True,'timing_qualified':True,'candidate_source_sha256':m['candidate_source_sha256'],
 'bitstream':str(out/bit.name),'mask':str(out/mask.name),'bitstream_sha256':sha(bit),'mask_sha256':sha(mask),
 'final_timing_report':str(reports[0]),'final_timing_sha256':sha(reports[0]),'timing_summary_rows':summary,
 'native_regressions':records,'hardware_programmed':False,'real_video_acceptance':False,'scope':'one RX capture edge change; B algorithm unchanged'}
 (out/'qualification.json').write_text(json.dumps(q,indent=2)+'\n')
 (out/'program.tcl').write_text('cfg_set_tcl_break -flag true\ncfg_connect -ip 127.0.0.1 -port 65420\ncfg_scan_chain\n'+f'cfg_assign_file -file {{{(out/bit.name).as_posix()}}} -device_index 0\n'+'cfg_set_device_property -device_index 0 -program 1\ncfg_program -device_index 0\ncfg_verify -device_index 0\ncfg_disconnect\ncfg_close\n')
 print('RX_EDGE_CANDIDATE_QUALIFIED',sha(bit))
if __name__=='__main__':main()
