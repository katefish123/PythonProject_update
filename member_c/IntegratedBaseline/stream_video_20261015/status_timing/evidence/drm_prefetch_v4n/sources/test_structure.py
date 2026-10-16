"""Reject the old ROM-to-RGB path and preserve the original API and ROM."""
from pathlib import Path
import argparse,re,hashlib
HERE=Path(__file__).resolve().parent
ORIGINAL=HERE/'status_overlay_original.v'
def verify(path):
 old=ORIGINAL.read_text();new=path.read_text()
 assert re.search(r'reg\s*\[159:0\]\s*row_bits\s*;',new),'missing independent 160-bit ROM row register'
 assert re.search(r'row_bits\s*<=\s*bits\s*;',new),'ROM result must be clocked before RGB mux'
 assert 'local_row_bits<=row_bits;' in new,'missing local register after inferred DRM output'
 assert 'segment_prefetch<=local_row_bits[' in new,'segment selection must start at local flop'
 assert 'active_segment<=segment_prefetch;' in new,'missing group-boundary segment register'
 assert 'active_segment[7-x[4:2]]' in new,'RGB must consume only the 8-bit segment'
 assert 'row_bits[159-x[9:2]]' not in new,'160-bit ROM output must not directly select RGB' 
 assert '&&bits[159-x[9:2]]' not in new,'old unregistered ROM-to-RGB path remains'
 literals=lambda s:re.findall(r"9'h[0-9a-f]+: bits=160'h[0-9a-f]+;",s)
 assert literals(new)==literals(old),'glyph ROM constants changed'
 assert new.split('reg[4:0]shown')[0]==old.split('reg[4:0]shown')[0],'API changed'
 print('PASS status structural ROM register cut, API and all '+str(len(literals(new)))+' ROM constants preserved')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--rtl',type=Path,default=HERE/'status_overlay.v');verify(p.parse_args().rtl)
