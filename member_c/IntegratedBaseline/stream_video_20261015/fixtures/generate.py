"""Independent integer solver + NumPy pixel oracle for streaming integration.
No HDL request/address data is read. Original B scalar model is used only to audit.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path
import numpy as np
from PIL import Image
S=1<<24
REFERENCE=Path(__file__).resolve().parents[2]/'a_black_sync_20261014/upstream/diagnostics/ddr_camera_black_20261014/b_algorithm/python'
BASE=Path('D:/FPGA/output/c_black_burst_merge_v3_20261015')
def trunc_div(n,d):
 if not d:raise ValueError('zero divisor')
 q=abs(int(n))//abs(int(d))
 return -q if (n<0)!=(d<0) else q
def solve_h(points,ow,oh,sw,sh):
 if not(2<=ow<=4096 and 2<=oh<=4096):raise ValueError('output dimensions')
 p=[[int(v) for v in pair] for pair in points]
 for i,(x,y) in enumerate(p):
  if not(0<=x<sw and 0<=y<sh):raise ValueError('corner outside source')
  a,b=p[(i+1)%4],p[(i+2)%4]
  if (a[0]-x)*(b[1]-a[1])-(a[1]-y)*(b[0]-a[0])<16:raise ValueError('nonconvex/small quad')
 (x0,y0),(x1,y1),(x2,y2),(x3,y3)=p
 dx1,dx2,dx3=x1-x2,x3-x2,x0-x1+x2-x3
 dy1,dy2,dy3=y1-y2,y3-y2,y0-y1+y2-y3
 det=dx1*dy2-dx2*dy1
 if abs(det)<16:raise ValueError('small determinant')
 g=trunc_div((dx3*dy2-dx2*dy3)*S,det)
 k=trunc_div((dx1*dy3-dx3*dy1)*S,det)
 h=[trunc_div((x1-x0)*S+g*x1,ow-1),trunc_div((x3-x0)*S+k*x3,oh-1),x0*S,
 trunc_div((y1-y0)*S+g*y1,ow-1),trunc_div((y3-y0)*S+k*y3,oh-1),y0*S,
 trunc_div(g,ow-1),trunc_div(k,oh-1),S]
 if abs(g)>4*S or abs(k)>4*S or any(not -(1<<39)<=v<(1<<39) for v in h):raise ValueError('H envelope')
 for x,y in [(0,0),(ow-1,0),(ow-1,oh-1),(0,oh-1)]:
  if h[6]*x+h[7]*y+h[8]<=1<<20:raise ValueError('unsafe denominator')
 return h
def rectify(image,h,active_w,out_h,storage_w,active_x,method):
 """Exact F24 H -> floor UQ12.8 coordinate -> original B RGB arithmetic."""
 sh,sw=image.shape[:2]
 yy,xx=np.mgrid[:out_h,:active_w].astype(np.int64)
 nx=h[0]*xx+h[1]*yy+h[2];ny=h[3]*xx+h[4]*yy+h[5];den=h[6]*xx+h[7]*yy+h[8]
 valid=(den>(1<<20))&(nx>=0)&(ny>=0)&(nx<(1<<48))&(ny<(1<<48))&(den<(1<<48))
 valid&=(nx<(den<<12))&(ny<(den<<12))
 safe_den=np.where(valid,den,1)
 sx=np.where(valid,(nx*256)//safe_den,0);sy=np.where(valid,(ny*256)//safe_den,0)
 if method=='nearest':
  x=(sx+128)>>8;y=(sy+128)>>8;inside=valid&(x<sw)&(y<sh)
  logical=image[np.clip(y,0,sh-1),np.clip(x,0,sw-1)].copy()
 elif method=='bilinear':
  inside=valid&(sx<=(sw-1)*256)&(sy<=(sh-1)*256)
  x=np.clip(sx>>8,0,sw-1);y=np.clip(sy>>8,0,sh-1)
  x1=np.minimum(x+1,sw-1);y1=np.minimum(y+1,sh-1)
  fx=(sx&255)[...,None];fy=(sy&255)[...,None]
  p=image.astype(np.int64)
  top=p[y,x]*(256-fx)+p[y,x1]*fx
  bottom=p[y1,x]*(256-fx)+p[y1,x1]*fx
  logical=((top*(256-fy)+bottom*fy)>>16).astype(np.uint8)
 else:raise ValueError('method')
 logical[~inside]=0
 storage=np.zeros((out_h,storage_w,3),np.uint8)
 storage[:,active_x:active_x+active_w]=logical
 return storage
def chart(sw,sh,generation):
 """Same procedural native pixel source used by the integration bench."""
 a=np.arange(sw*sh,dtype=np.uint64).reshape(sh,sw)
 return np.stack(((a+generation*13)%251,(a//7+generation*29)%253,(a//13+generation*41)%255),axis=-1).astype(np.uint8)
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def save_rgb(path,image):
 packed=(image[...,0].astype(np.uint32)<<16)|(image[...,1].astype(np.uint32)<<8)|image[...,2]
 np.savetxt(path,packed.reshape(-1),fmt='%06x')
 Image.fromarray(image).save(path.with_suffix('.png'))
 return {'hex_sha256':sha(path),'png_sha256':sha(path.with_suffix('.png')),'pixels':int(packed.size)}
def audit(image,expected,h,points,aw,oh,ax,method):
 from brect.fixed import solve_fixed,map_fixed,sample_fixed
 assert h==solve_fixed(points,aw,oh,image.shape[1],image.shape[0])
 rng=np.random.default_rng(20261015)
 positions=np.r_[0,aw-1,aw*(oh-1),aw*oh-1,rng.integers(aw*oh,size=1024)]
 for position in positions:
  y,x=divmod(int(position),aw)
  sx,sy,valid=map_fixed(h,x,y)
  scalar=sample_fixed(image,sx,sy,method) if valid else np.zeros(3,np.uint8)
  np.testing.assert_array_equal(expected[y,x+ax],scalar)
 assert not expected[:,:ax].any() and not expected[:,ax+aw:].any()
 return len(positions)
def generate(output,sizes):
 sys.path.insert(0,str(REFERENCE))
 configs={'reduced':(128,48,32,48,29,1,[(34,4),(93,6),(103,42),(25,39)]),
 'fullhd':(1920,1080,768,1080,765,1,[(650,70),(1250,110),(1320,1010),(590,960)])}
 records=[]
 for name in sizes:
  sw,sh,ow,oh,aw,ax,points=configs[name]
  h=solve_h(points,aw,oh,sw,sh)
  corners=''.join(f'{v:03x}' for pair in points for v in pair)
  for variant,generation in enumerate((11,29,43)):
   folder=output/name/f'variant{variant}';folder.mkdir(parents=True,exist_ok=True)
   source=chart(sw,sh,generation)
   artifacts={'source':save_rgb(folder/'source.hex',source)}
   checks=0
   for method in ('bilinear','nearest'):
    expected=rectify(source,h,aw,oh,ow,ax,method)
    checks+=audit(source,expected,h,points,aw,oh,ax,method)
    artifacts['expected_'+method]=save_rgb(folder/f'expected_{method}.hex',expected)
   metadata={'size':name,'variant':variant,'source_generation_seed':generation,'source':[sw,sh],
   'storage':[ow,oh],'logical':[aw,oh],'active_x':ax,'corners':points,'corners96_hex':corners,
   'H_q24_signed':h,'H_40bit_hex':[f'{v&((1<<40)-1):010x}' for v in h],
   'independent_reference':True,'hdl_q_requests_used':False,'scalar_audit_pixels':checks,
   'source_formula':'R=(addr+gen*13)%251;G=(addr//7+gen*29)%253;B=(addr//13+gen*41)%255',
   'artifacts':artifacts,'synthetic':True,'hardware_accepted':False}
   (folder/'metadata.json').write_text(json.dumps(metadata,indent=2)+'\n')
   (folder/'corners96.hex').write_text(corners+'\n')
   records.append({'path':str(folder),'metadata_sha256':sha(folder/'metadata.json')})
   print(f'FIXTURE_READY {name} variant{variant} seed={generation} corners96={corners} scalar_checks={checks}',flush=True)
 output.mkdir(parents=True,exist_ok=True)
 audited_files=[REFERENCE/'brect/fixed.py',REFERENCE/'brect/golden.py',
 BASE/'vendor/b/rtl/homography_solver.v',BASE/'vendor/b/rtl/perspective_coord.v',BASE/'vendor/b/rtl/scaled_div_pipe.v',
 BASE/'vendor/b/rtl/perspective_core.v',BASE/'vendor/b/rtl/bilinear_interp.v',
 Path(__file__).parent.parent.parent/'inline_geometry_20261014/fixtures.py',Path(__file__)]
 manifest={'fixtures':records,'audited_sources':{str(p):sha(p) for p in audited_files}}
 (output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,default=Path(__file__).parent/'generated')
 parser.add_argument('--sizes',nargs='+',choices=['reduced','fullhd'],default=['reduced','fullhd'])
 parser.add_argument('--baseline',type=Path,default=BASE)
 args=parser.parse_args();BASE=args.baseline.resolve();generate(args.output,args.sizes)
