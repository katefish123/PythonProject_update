"""Decode new diagnostic rows only with an explicitly qualified bit binding."""
import argparse,json
from pathlib import Path

def fields(rows):
 def get(row,shift,width):
  s=rows.get(row,'')
  if len(s)!=20 or any(c not in '0123456789abcdefABCDEF' for c in s):return None
  return (int(s,16)>>shift)&((1<<width)-1)
 return dict(reject12=get('06',32,32),reject13=get('06',0,32),reject14=get('07',32,32),reject15=get('07',0,32),
  write_commands=get('12',32,32),read_commands=get('12',0,32),write_wait_ui_cycles=get('13',32,32),read_wait_ui_cycles=get('13',0,32),display_underrun=get('16',79,1),scan_count=get('17',48,32))

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('decoded_json',type=Path);p.add_argument('--qualification',required=True,type=Path);p.add_argument('--bit-sha256',required=True);p.add_argument('--output',required=True,type=Path);a=p.parse_args()
 q=json.loads(a.qualification.read_text())
 if not q.get('timing_qualified') or not q.get('diagnostic_observer_sim_sha256') or q.get('bitstream_sha256')!=a.bit_sha256:
  raise ValueError('Exact diagnostic qualification/hash required; never decode old c129 rows with this schema')
 data=json.loads(a.decoded_json.read_text(encoding='utf-8-sig'));samples=data if isinstance(data,list) else data.get('samples',[data])
 result=[]
 for s in samples:
  d=s.get('decoded',s);result.append({'bitstream_sha256':a.bit_sha256,'image':d.get('image'),'diagnostics':fields(d.get('rows',{}))})
 a.output.write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps(result,indent=2))
