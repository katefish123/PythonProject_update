"""Decode native debug_hex_overlay segment samples; no image edits or hardware IO."""
import argparse
import hashlib
import json
from pathlib import Path
import cv2
import numpy as np

PATTERNS = [126,48,109,121,51,91,95,112,127,123,119,31,78,61,79,71]
POINTS = [(6,2),(9,6),(9,13),(6,16),(1,13),(1,6),(6,9)]

def decode(path, inverted):
    a = cv2.imread(str(path))
    if a is None or a.shape != (1080,1920,3):
        raise ValueError('Native 1920x1080 PNG required')
    if inverted:
        a = a[::-1]
    rows = {}
    for row in range(24):
        text = ''
        for col in range(3,23):
            value = 0
            for bit,(x,y) in enumerate(POINTS):
                block = a[64+row*32+y:64+row*32+y+2,col*16+x+1:col*16+x+3]
                value |= int(np.max(block)>180) << (6-bit)
            text += format(PATTERNS.index(value),'x') if value in PATTERNS else '?'
        rows[format(row,'02x')] = text
    fields = {}
    if all('?' not in rows[k] for k in ['00','01','02','03','04','05','0d']) and int(rows['00'],16)>>63==0:
        r = {k:int(v,16) for k,v in rows.items() if '?' not in v}
        fields = dict(input=r['01']>>32,admitted=r['01']&0xffffffff,
            dropped=r['02']>>32,rejected=r['02']&0xffffffff,
            raw=r['03']>>32,corrected=r['03']&0xffffffff,
            displayed=r['04']>>32,age_ms=r['04']&0xffffffff,
            fifo_peak=(r['05']>>43)&2047,recovery=r['05']&2047,
            current_mask=(r['0d']>>26)&31,first_mask=(r['0d']>>10)&31,
            pix_frame_id=(r['00']>>31)&0xffffffff,image_valid=bool(r['00']&1),
            pix_raw=bool(r['00']&4),pix_bank=(r['00']>>1)&1,pix_base=(r['00']>>3)&0xfffffff)
    return {'image':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
            'capture_inverted_for_sampling':inverted,'rows':rows,'decoded_fields':fields}

if __name__ == '__main__':
    p=argparse.ArgumentParser();p.add_argument('directory',type=Path);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--glob',default='camera_raw*.png',help='Native PNG filename pattern, e.g. *.png for OBS screenshots')
    p.add_argument('--capture-inverted',action='store_true');args=p.parse_args()
    files=sorted(args.directory.glob(args.glob))
    if not files:raise ValueError('No native PNG matched '+args.glob)
    result=[decode(f,args.capture_inverted) for f in files]
    args.output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))
