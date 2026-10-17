"""Synthetic-only vectors from the existing, separate float/integer models."""
from pathlib import Path
import hashlib,json,random,sys
H=Path(__file__).resolve().parent
sys.path.insert(0,str(H.parent/'lens_model_20261015'))
from lens_golden import Profile,FrameMap
from lens_fixed import FixedFrameMap,NumericReject,encode,div,add,SCALE
sys.path.insert(0,str(H.parent/'a_black_sync_20261014/upstream/diagnostics/ddr_camera_black_20261014/b_algorithm/python'))
from brect.fixed import interpolate
from corner_preparation import fit_ideal_h
O=Path('D:/FPGA/output/lens_vectors_20261017');O.mkdir(exist_ok=True)
rng=random.Random(170017);records=[];composed_records=[];pixels=[];max_error=0.;corner_case=None;h_only_differences={n:0 for n in ('k1','k2','p1','p2')}
def pattern(x,y):return [(x*3+y*7)%256,(x*11+y*5)%256,(x*17+y*13)%256]
for n in range(1024):
 family=n%7
 coefficients=[0.,0.,0.,0.]
 if 1<=family<=4:coefficients[family-1]=[-.15,.06,.004,-.003][family-1]
 if family==5:coefficients=[-.15,.06,.004,-.003]
 p=Profile(1920,1080,913.7,901.55,960.25,539.75,*coefficients,'synthetic-RTL-vector')
 h=(.91,.012,-70.,-.008,1.03,25.,.000015,-.00002,1.) if family==6 else (1.,0.,0.,0.,1.,0.,0.,0.,1.)
 u,v=(rng.randrange(1920),rng.randrange(1080))
 if n<4:u,v=[(0,0),(1919,0),(0,1079),(1919,1079)][n]
 if n%97==0:
  p=Profile(1920,1080,1.,1.,0.,0.,*coefficients,'synthetic-domain-rejection');u,v=1919,1079
 if family==5 and n%97!=0:
  known_ideal=[(250.,130.),(1650.,190.),(1600.,930.),(220.,900.)]
  raw=[(q.x,q.y) for q in [FrameMap(p).map(*pt) for pt in known_ideal]]
  h,recovered=fit_ideal_h(p,raw,1920,1080)
  corner_case={'synthetic':True,'raw_corners':raw,'recovered_ideal_corners':recovered,'known_ideal_corners':known_ideal,'ideal_H':h}
 fixed=FixedFrameMap(p,h);hq=fixed.h_q
 den=add(hq[6]*u,hq[7]*v,hq[8]);iu=div(add(hq[0]*u,hq[1]*v,hq[2]),den);iv=div(add(hq[3]*u,hq[4]*v,hq[5]),den)
 invalid=False;inside=False;x=y=0
 try:
  q=fixed.map(u,v);truth=FrameMap(p,h).map(u,v)
  x,y,inside=q.x_q,q.y_q,q.inside
  max_error=max(max_error,abs(x/SCALE-truth.x),abs(y/SCALE-truth.y))
  if 1<=family<=4 and max(abs(truth.x-iu/SCALE),abs(truth.y-iv/SCALE))>.125:h_only_differences[('k1','k2','p1','p2')[family-1]]+=1
 except (NumericReject,ValueError):invalid=True
 version=n+1;hframe=n+1001;request_frame=hframe
 if n%113==0:request_frame=hframe+1;invalid=True;inside=False;x=y=0
 rgb=[0,0,0]
 if inside and not invalid:
  xx,yy=x>>30,y>>30;xx1=min(xx+1,p.width-1);yy1=min(yy+1,p.height-1)
  rgb=interpolate([pattern(xx,yy),pattern(xx1,yy),pattern(xx,yy1),pattern(xx1,yy1)],(x>>22)&255,(y>>22)&255)
 pixels.append(''.join(f'{int(c):02x}' for c in rgb))
 values=[(x,64),(y,64),(int(inside),1),(int(invalid),1),(iu,64),(iv,64),(n+1,32),(request_frame,32),(version,32),(hframe,32),(p.width,13),(p.height,13)]
 values += [(encode(getattr(p,name)),64) for name in ('fx','fy','cx','cy','k1','k2','p1','p2')]
 word=0;shift=0
 for value,bits in values:word|=(int(value)&((1<<bits)-1))<<shift;shift+=bits
 assert shift==924
 records.append(f'{word:0231x}')
 for coefficient in hq:word|=(coefficient&((1<<64)-1))<<shift;shift+=64
 word|=u<<shift;shift+=12;word|=v<<shift;shift+=12
 assert shift==1524
 composed_records.append(f'{word:0381x}')
assert all(v>100 for v in h_only_differences.values())
assert max_error<=.125
(O/'vectors.hex').write_text('\n'.join(records)+'\n')
(O/'composed_vectors.hex').write_text('\n'.join(composed_records)+'\n')
(O/'expected_pixels.hex').write_text('\n'.join(pixels)+'\n')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
manifest={'scope':'synthetic vectors for Brown-only and destination-H-Brown RTL; no DDR/HDMI or physical optics',
 'vectors':len(records),'maximum_float_vs_fixed_source_pixel_error':max_error,
 'H_only_negative_controls_detected':h_only_differences,'real_calibration':False,
 'vectors_sha256':sha(O/'vectors.hex'),
 'expected_pixels_sha256':sha(O/'expected_pixels.hex'),
 'composed_vectors_sha256':sha(O/'composed_vectors.hex'),
 'B_fixed_sampling_reference_sha256':sha(H.parent/'a_black_sync_20261014/upstream/diagnostics/ddr_camera_black_20261014/b_algorithm/python/brect/fixed.py'),
 'reference_sha256':{n:sha(H.parent/'lens_model_20261015'/n) for n in ('lens_golden.py','lens_fixed.py')},
 'generator_sha256':sha(Path(__file__))}
manifest['synthetic_inverse_corner_H_case']=corner_case
manifest['corner_preparation_sha256']=sha(H/'corner_preparation.py')
(O/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('SYNTHETIC_VECTORS',len(records),'float/fixed max error',max_error,'H-only negatives',h_only_differences)
