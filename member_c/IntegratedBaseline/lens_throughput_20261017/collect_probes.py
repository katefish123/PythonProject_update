"""Isolated registered-input ALU PDS evidence, never a board qualification."""
from pathlib import Path
import hashlib,json,re,zipfile
H=Path(__file__).resolve().parent;E=H/'evidence';E.mkdir(exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):
 b=p.read_bytes();return b.decode('utf-16' if b.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8-sig',errors='replace')
results={};archive=E/'isolated_registered_PDS.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
 for label,root in [('v1','D:/FPGA/output/lens_alu_registered_probe_20261017'),('v2','D:/FPGA/output/lens_alu_registered_probe_20261017_v2')]:
  for kind in ('reference','fast'):
   p=Path(root)/kind;log=read(p/'pds_stdout.log');m=json.loads((p/'input_manifest.json').read_text())
   source=p/('q30_alu.v' if kind=='reference' else 'q30_alu_fast.v')
   assert sha(source)==m['frozen_source_sha256'] and sha(p/'q30_probe_top.v')==m['wrapper_sha256']
   assert sha(p/'probe.fdc')==m['fdc_sha256'] and sha(p/'build.tcl')==m['tcl_sha256']
   assert 'Executing : report_timing successfully.' in log and not re.search(r'^E:',log,re.M),'probe flow unfinished/failed'
   if label=='v2':
    current=H/'q30_alu_fast.v' if kind=='fast' else H.parent/'lens_model_next/q30_alu.v'
    assert sha(current)==sha(source),('current probe drift',kind)
   timing=p/'build/report_timing/q30_probe_top.rtr';text=read(timing)
   assert 'Design Summary : All Constraints Met.' in text
   checks={}
   for check in ('Setup','Hold'):
    for corner in ('Slow','Fast'):
     section=re.search(check+r' Summary\('+corner+r' Corner\):\s*\n(.*?)(?=\n\s*\n)',text,re.S)[1]
     row=re.search(r'processing_clock\s+processing_clock\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(\d+)\s+(\d+)',section)
     assert row and float(row[1])>=0 and int(row[3])==0
     checks[check+'_'+corner]={'slack_ns':float(row[1]),'failing_endpoints':int(row[3]),'total_endpoints':int(row[4])}
   synth=p/'build/synthesize/q30_probe_top.snr';st=read(synth)
   resources={'synthesis_LUTs':int(re.search(r'Total LUTs:\s*(\d+)',st)[1]),
    'synthesis_registers':int(re.search(r'Total Registers:\s*(\d+)',st)[1]),
    'synthesis_APMs':float(re.search(r'Total APMs =\s*([\d.]+)',st)[1])}
   results[label+'_'+kind]={'scope':'isolated registered-input/output wrapper,external IO unconstrained; not board timing',
    'period_ns':17.508,'source_sha256':sha(source),'timing':checks,'resources':resources,
    'report_sha256':sha(timing),'log_sha256':sha(p/'pds_stdout.log')}
   for f in [source,p/'q30_probe_top.v',p/'probe.fdc',p/'build.tcl',p/'input_manifest.json',p/'pds_stdout.log',timing,synth,p/'build/build.pds']:
    z.write(f,label+'_'+kind+'/'+f.relative_to(p).as_posix())
summary={'board_timing_qualified':False,'enterprise_acceptance':False,'hardware_acceptance':False,
 'scope':'Isolated ALU reg-to-reg timing and synthesis resource comparison only. No board pins,external IO delay,DDR,HDMI,video rate or bitstream qualification.',
 'results':results,'archive_sha256':sha(archive),
 'v1_note':'Minimum observed slow setup margin0.023ns motivated94-bit remainder/single subtract and separate rounding cycle in v2.'}
(H/'probe_results.json').write_text(json.dumps(summary,indent=2)+'\n')
print('PASS isolated PDS evidence; NOT board timing qualification:',json.dumps({k:v['timing']['Setup_Slow']['slack_ns'] for k,v in results.items()}))
