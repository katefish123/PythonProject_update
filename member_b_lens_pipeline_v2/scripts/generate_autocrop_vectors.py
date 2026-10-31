"""Every native output boundary pixel plus an interior grid, both samplers."""
import json
from pathlib import Path
import sys
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'python'))
from brect.calibration import load_calibration
from brect.fixed import map_fixed, addresses, interpolate
from brect.lens import _map_hardware
from export_lens_viewport import export
from generate_lens_vectors import source_pixel


def generate():
    calibration=ROOT/'calibration/r50_18mm_hdmi_trial.json'
    exported=export(calibration,ROOT/'examples/r50_18mm_viewport')
    p=load_calibration(calibration);hw=p.to_hardware();h=exported['H_q24']
    width,height=exported['framing']['output_size']
    boundary={(x,y) for x in range(width) for y in (0,height-1)}
    boundary.update((x,y) for y in range(height) for x in (0,width-1))
    points=set(boundary)
    points.update((int(x),int(y)) for y in np.linspace(0,height-1,19).astype(int)
                  for x in np.linspace(0,width-1,33).astype(int))
    rows=[]
    for x,y in sorted(points,key=lambda point:(point[1],point[0])):
        u,v,good=map_fixed(h,x,y);sx,sy,good=_map_hardware(hw,u,v,in_error=not good)
        for nearest in (0,1):
            inside,aa,fx,fy=addresses(sx,sy,p.width,p.height,'nearest' if nearest else 'bilinear')
            if not (inside and good):raise AssertionError(f'Unsafe exported viewport at {x},{y}')
            rgb=interpolate([source_pixel(a) for a in aa],fx,fy)
            packed=(int(rgb[0])<<16)|(int(rgb[1])<<8)|int(rgb[2])
            rows.append(' '.join(map(str,[x,y,nearest,*aa,fx,fy,packed])))
    (ROOT/'vectors').mkdir(exist_ok=True)
    (ROOT/'vectors/lens_autocrop.txt').write_text('\n'.join(rows)+'\n')
    manifest={'transactions':len(rows),'distinct_boundary_pixels':len(boundary),
              'output_size':[width,height],'samplers':['bilinear','nearest'],
              'source_outside_pixels':0,'full_grid_proof':exported['framing']}
    (ROOT/'vectors/lens_autocrop_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    return manifest


if __name__=='__main__':
    result=generate()
    print(json.dumps({key:value for key,value in result.items() if key!='full_grid_proof'},indent=2))
