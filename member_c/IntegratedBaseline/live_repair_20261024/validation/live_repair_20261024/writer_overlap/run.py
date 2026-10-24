"""Isolated serial writer test; no PDS, ports, or hardware."""
from pathlib import Path
import hashlib,json,subprocess,sys
ROOT=Path(__file__).resolve().parent
TOOLS=Path('D:/softwares/modelsim/win64')
OLD=Path('D:/FPGA/deliveries/FullHD_Lens_IntegratedRepair_20261023/sources/continuous_capture_writer.v')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def run(name,rtl,args,negative=False,bench='tb_writer_overlap'):
 out=ROOT/name;out.mkdir(exist_ok=False)
 for dst,src in [('continuous_capture_writer.v',rtl),(bench+'.sv',ROOT/(bench+'.sv'))]:
  (out/dst).write_bytes(src.read_bytes())
 cmds=[['vlib.exe','work'],['vlog.exe','-sv','continuous_capture_writer.v',bench+'.sv'],['vsim.exe','-c',bench,*args,'-do','run -all; quit -f']]
 records=[]
 for i,cmd in enumerate(cmds):
  p=subprocess.run([str(TOOLS/cmd[0]),*cmd[1:]],cwd=out,capture_output=True,text=True)
  log=out/f'step{i}.log';log.write_text(p.stdout+p.stderr)
  records.append(dict(argv=cmd,exit_code=p.returncode,log_sha256=sha(log)))
  if i<2 and (p.returncode or '** Error:' in log.read_text()):raise RuntimeError(str(log))
 text=(out/'step2.log').read_text()
 good=('BOUNDED_QUEUE_OVERFLOW' in text) if negative else (('PASS lifecycle' if bench=='tb_writer_lifecycle' else 'PASS writer bounded16') in text and '** Fatal:' not in text and '** Error:' not in text and 'Errors: 0, Warnings: 0' in text)
 record=dict(expected='bounded queue overflow' if negative else 'pass',matched=good,rtl_sha256=sha(out/'continuous_capture_writer.v'),bench_sha256=sha(out/(bench+'.sv')),commands=records)
 (out/'verification.json').write_text(json.dumps(record,indent=2)+'\n')
 print(name,good)
 if not good:raise RuntimeError(str(out/'step2.log'))
if __name__=='__main__':
 name=sys.argv[1];mode=name.split('_final')[0]
 if mode=='old_red':run(name,OLD,['+DELAY=20','+PERIOD=3'],True)
 elif mode=='old_limit':run(name,OLD,['+DELAY=40','+PERIOD=3'],True)
 elif mode=='new_green':run(name,ROOT/'continuous_capture_writer.v',['+DELAY=20','+PERIOD=3'])
 elif mode=='new_limit':run(name,ROOT/'continuous_capture_writer.v',['+DELAY=40','+PERIOD=3'],True)
 elif mode=='multi':run(name,ROOT/'continuous_capture_writer.v',['+DELAY=20','+PERIOD=5','+CONTROL=1','+FRAMES=3'])
 elif mode=='reset':run(name,ROOT/'continuous_capture_writer.v',['+DELAY=20','+PERIOD=5','+CONTROL=1','+RESET=1'])
 elif mode=='lifecycle':run(name,ROOT/'continuous_capture_writer.v',[],bench='tb_writer_lifecycle')
 elif mode=='rate_old':run(name,OLD,['+DELAY=50','+PERIOD=7'],True)
 elif mode=='rate_new':run(name,ROOT/'continuous_capture_writer.v',['+DELAY=50','+PERIOD=7'])
 elif mode.startswith('control'):
  bad=int(mode[-1]);run(name,ROOT/'continuous_capture_writer.v',['+DELAY=20','+PERIOD=5','+CONTROL=1',f'+BAD={bad}'])
 else:raise ValueError(mode)
