"""Deterministic lens and complete cache/interpolation reference transactions."""
from pathlib import Path
import json
import sys
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'python'))
from brect.calibration import load_calibration
from brect.lens import _map_hardware
from brect.fixed import addresses, interpolate, map_fixed

def source_pixel(address):
    return [(address*17+3) & 255, (address >> 3) & 255, ((address*11) >> 7) & 255]

def generate():
    profile = load_calibration(ROOT / 'calibration/r50_18mm_hdmi_trial.json')
    hardware = profile.to_hardware()
    (ROOT / 'vectors').mkdir(exist_ok=True)
    rng = np.random.default_rng(181022)
    samples = [(x*256+fx, y*256+fy) for x,y in [(0,0),(1919,0),(0,1079),(1919,1079),(933,525),(4095,4095)]
               for fx,fy in [(0,0),(127,128),(255,255)]]
    samples += list(zip(rng.integers(0, 1<<20, 512).tolist(), rng.integers(0, 1<<20, 512).tolist()))
    lens = []
    for tag,(u,v) in enumerate(samples):
        incoming_error = int(tag % 19 == 7)
        sx,sy,valid = _map_hardware(hardware,int(u),int(v),in_error=bool(incoming_error))
        lens.append(f'{tag} {u} {v} {incoming_error} {int(not valid)} {sx} {sy}')
    (ROOT / 'vectors/lens_coord.txt').write_text('\n'.join(lens)+'\n')
    S=1<<24
    transforms = [
        [S,0,0,0,S,0,0,0,S],
        [S,0,S//4,0,S,S//2,0,0,S],
        [int(.93*S),int(.02*S),20*S,int(-.01*S),int(.96*S),16*S,int(.00003*S),int(.00002*S),S],
        [S,0,-S,0,S,0,0,0,S],
        [S,0,0,0,S,0,0,0,S//16],
    ]
    positions=[(0,0),(1919,0),(0,1079),(1919,1079),(933,525),(4095,4095),(1920,1080)]
    positions+=list(zip(rng.integers(0,1920,160).tolist(),rng.integers(0,1080,160).tolist()))
    transactions=[]
    for index,(x,y) in enumerate(positions):
        for which,h in enumerate(transforms):
            nn=(index+which)%2;geometry=int(index%23!=5)
            u,v,h_valid=map_fixed(h,x,y)
            sx,sy,l_valid=_map_hardware(hardware,u,v,in_error=not h_valid)
            inside,aa,xf,yf=addresses(sx,sy,1920,1080,'nearest' if nn else 'bilinear')
            inside=bool(inside and l_valid and geometry)
            if not inside:aa=[0]*4;xf=yf=0
            rgb=interpolate([source_pixel(a) for a in aa],xf,yf) if inside else np.zeros(3,np.uint8)
            packed=(int(rgb[0])<<16)|(int(rgb[1])<<8)|int(rgb[2])
            fields=[x,y,nn,geometry,*h,int(inside),int(not l_valid),*aa,xf,yf,packed]
            transactions.append(' '.join(map(str,fields)))
    (ROOT / 'vectors/lens_integration.txt').write_text('\n'.join(transactions)+'\n')
    manifest=dict(lens_coordinates=len(lens),integration_transactions=len(transactions),
                  input_size=[1920,1080],profile_id=profile.metadata.get('profile_id','r50_18mm'))
    (ROOT / 'vectors/lens_manifest.json').write_text(json.dumps(manifest,indent=2))
    return manifest

if __name__=='__main__':print(json.dumps(generate(),indent=2))
