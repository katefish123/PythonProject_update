"""Describe saved readback differences; do not alter masks or waive mismatches."""
from pathlib import Path
from collections import Counter
import json
R=Path(__file__).resolve().parents[2]
H=R/'results/hardware_20261009'
P=R/'diagnostics/camera_passthrough_rx_first/results/generate_bitstream/hdmi_camera_passthrough_rx_first_top.sbit'
paths=[P,P.with_suffix('.smsk'),H/'rdfile_2026_10_10_13_38_8',H/'rdfile_2026_10_10_13_40_25']
data=[p.read_bytes() for p in paths]
metadata=[{'path':str(p),'length':len(b),'head_hex':b[:48].hex()} for p,b in zip(paths,data)]
results={'files':metadata}
for a,b,label in [(data[0],data[2],'expected_vs_first_1mhz'),(data[0],data[3],'expected_vs_second_1mhz'),(data[2],data[3],'between_1mhz_reads')]:
    if len(a)!=len(b):
        results[label]={'different_lengths':True}
        continue
    counts=Counter()
    first=[]
    changed=0
    for i,(x,y) in enumerate(zip(a,b)):
        n=(x^y).bit_count()
        if n:
            changed+=n;counts[i//65536]+=n
            if len(first)<24:first.append({'byte_offset':i,'a':x,'b':y})
    results[label]={'raw_changed_bits':changed,'first_differences':first,
                    'changed_bits_by_64k_block':dict(counts)}
print(json.dumps(results,indent=2))
(H/'readback_analysis_resume_20261010.json').write_text(json.dumps(results,indent=2)+'\n',encoding='utf-8')
