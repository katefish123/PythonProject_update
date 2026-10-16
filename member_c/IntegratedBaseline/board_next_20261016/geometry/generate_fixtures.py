"""Synthetic original1920x1080 RGB frames and independent fixed-H references.
The user screenshots are diagnostics only and never used as source-frame input.
"""
from pathlib import Path
import importlib.util,json,sys,hashlib
import numpy as np
from PIL import Image,ImageDraw,ImageFont
here=Path(__file__).resolve().parent
existing=here.parent.parent/'stream_video_20261015/fixtures/generate.py'
spec=importlib.util.spec_from_file_location('independent_fixed',existing);ref=importlib.util.module_from_spec(spec);spec.loader.exec_module(ref)
sys.path.insert(0,str(ref.REFERENCE))
from brect.fixed import solve_fixed,map_fixed
SW,SH,AW,OH=1920,1080,765,1080
colors=np.array([(224,32,32),(32,208,32),(224,208,32),(32,32,224)],np.uint8)
def masks(a):
 r,g,b=[a[...,i].astype(np.int32) for i in range(3)]
 y=(r>=64)&(g>=64)&(r>=b+32)&(g>=b+32)&(2*r<=3*g)&(2*g<=3*r)
 return [(r>=64)&(r>=g+32)&(r>=b+32)&~y,(g>=64)&(g>=r+32)&(g>=b+32)&~y,y,(b>=64)&(b>=r+32)&(b>=g+32)]
def detect(a):
 stats=[];p=[];ok=True
 for m in masks(a):
  y,x=np.nonzero(m);n=len(x)
  if not n:stats.append({'n':0});p.append([0,0]);ok=False;continue
  w=int(x.max()-x.min()+1);h=int(y.max()-y.min()+1)
  point=[int((x.astype(np.int64).sum()+n//2)//n),int((y.astype(np.int64).sum()+n//2)//n)]
  good=16<=n<=4096 and max(w,h)<=129 and min(w,h)>=3 and max(w,h)<=6*min(w,h) and n*2>=w*h
  stats.append({'n':n,'bbox':[int(x.min()),int(y.min()),int(x.max()),int(y.max())],'occupancy':n/(w*h),'good':good});p.append(point);ok&=good
 cross=[]
 for i in range(4):
  a0,a1,a2=np.array(p[i]),np.array(p[(i+1)%4]),np.array(p[(i+2)%4]);d0=a1-a0;d1=a2-a1;cross.append(int(d0[0]*d1[1]-d0[1]*d1[0]))
 area2=cross[0]+cross[2]
 ok&=min(cross)>=64 and area2>=2*(SW*SH//50) and p[1][0]+p[2][0]>=p[0][0]+p[3][0]+SH//16 and p[2][1]+p[3][1]>=p[0][1]+p[1][1]+SH//16
 return bool(ok),p,stats,{'turns':cross,'area2':area2}
def floating_h(p):
 src=[(0,0),(AW-1,0),(AW-1,OH-1),(0,OH-1)];rows=[];vals=[]
 for (u,v),(x,y) in zip(src,p):
  rows += [[u,v,1,0,0,0,-x*u,-x*v],[0,0,0,u,v,1,-y*u,-y*v]];vals += [x,y]
 return np.r_[np.linalg.solve(np.array(rows,float),np.array(vals,float)),1].reshape(3,3)
def page(kind=0):
 im=Image.new('RGB',(1000,1414),'white');d=ImageDraw.Draw(im);font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',22)
 d.text((180,230),'FOUR COLOUR CALIBRATION / V1',fill='black',font=font)
 d.text((180,265),'RED TL / GREEN TR / YELLOW BR / BLUE BL',fill='black',font=font)
 for n in range(1,8):x=118+n*764/8;d.line((x,340,x,1150),fill='#808080',width=2)
 for n in range(2,12):y=167+n*1079/12;d.line((180,y,820,y),fill='#808080',width=2)
 for i,(x,y) in enumerate([(118,167),(882,167),(882,1246),(118,1246)]):
  col=tuple(int(v) for v in colors[i if kind!=1 else (3 if i==0 else 0 if i==3 else i)])
  if kind==2 and i==2:col=(255,255,255)
  if kind==3:col=(255,255,255)
  d.rectangle((x-15,y-15,x+15,y+15),fill=col)
 d.text((120,1320),'MARKER CENTRES DEFINE THE RECTIFIED BOUNDARY',fill='black',font=font)
 return im
out=here/'fixtures';out.mkdir(exist_ok=True)
page().save(out/'matching_four_color_test_page.png',dpi=(150,150))
page().save(out/'matching_four_color_test_page.pdf','PDF',resolution=150)
yy,xx=np.mgrid[:SH,:SW];flat=np.stack((xx.ravel(),yy.ravel(),np.ones(SW*SH)))
configs=[('canonical',[(650,70),(1250,110),(1320,1010),(590,960)],0,True),('right_side',[(1100,100),(1700,160),(1650,950),(1150,900)],0,True),('swapped_colors',[(650,70),(1250,110),(1320,1010),(590,960)],1,False),('missing_yellow',[(650,70),(1250,110),(1320,1010),(590,960)],2,False),('unmarked_grid',[(650,70),(1250,110),(1320,1010),(590,960)],3,False)]
records=[];tables=[]
for name,points,kind,want in configs:
 H=floating_h(points);uv=np.linalg.inv(H)@flat;u=uv[0]/uv[2];v=uv[1]/uv[2]
 px=np.floor(118+u+.5).astype(int);py=np.floor(167+v+.5).astype(int)
 inside=(px>=0)&(px<1000)&(py>=0)&(py<1414);image=np.full((SW*SH,3),176,np.uint8);paper=np.asarray(page(kind));image[inside]=paper[py[inside],px[inside]];image=image.reshape(SH,SW,3)
 valid,p,stats,geometry=detect(image);assert valid==want,(name,p,stats,geometry)
 folder=out/name;folder.mkdir(exist_ok=True);Image.fromarray(image).save(folder/'source_1920x1080.png')
 selected=np.logical_or.reduce(masks(image));ys,xs=np.nonzero(selected)
 events=(xs.astype(np.uint64)<<36)|(ys.astype(np.uint64)<<24)|(image[ys,xs,0].astype(np.uint64)<<16)|(image[ys,xs,1].astype(np.uint64)<<8)|image[ys,xs,2]
 np.savetxt(folder/'events.hex',events,fmt='%012x')
 packed=''.join(f'{v:03x}' for pair in p for v in pair);tables.append(f'{folder.as_posix()}/events.hex {int(valid)} {packed} {len(events)}')
 rec={'name':name,'synthetic_original_frame':True,'source_size':[SW,SH],'valid':valid,'detected_color_order':['red TL','green TR','yellow BR','blue BL'],'corners':p,'corners96_hex':packed,'statistics':stats,'geometry':geometry,'events':len(events)}
 if valid:
  h=ref.solve_h(p,AW,OH,SW,SH);assert h==solve_fixed(p,AW,OH,SW,SH)
  result=ref.rectify(image,h,AW,OH,768,1,'bilinear');Image.fromarray(result).save(folder/'expected_storage_768x1080.png')
  probes=[];errors=[]
  for v in [0,270,540,810,1079]:
   for u in [0,191,382,573,764]:
    sx,sy,good=map_fixed(h,u,v);assert good
    independent=H@np.array([u,v,1.]);independent=independent[:2]/independent[2]
    err=float(np.max(np.abs(np.array([sx,sy])/256-independent)));errors.append(err)
    probes.append({'output':[u,v],'source_UQ12_8':[sx,sy],'source_float_from_original_grid':independent.tolist(),'error_source_pixels':err})
  assert max(errors)<1.5,max(errors)
  rec.update(H_q24_signed=h,homography_probe_grid=probes,max_grid_error_source_pixels=max(errors),logical_output=[AW,OH],storage_output=[768,1080],active_x=1,black_padding=[1,2],independent_B_scalar_solver_match=True)
 (folder/'metadata.json').write_text(json.dumps(rec,indent=2)+'\n');records.append(rec)
(out/'cases.txt').write_text('\n'.join(tables)+'\n')
(out/'reference.json').write_text(json.dumps({'synthetic':True,'screenshots_used_as_raw':False,'matching_physical_page':'matching_four_color_test_page.pdf','page_marker_center_pixels':[[118,167],[882,167],[882,1246],[118,1246]],'fixtures':records,'reference_sources':{str(existing):hashlib.sha256(existing.read_bytes()).hexdigest(),str(ref.REFERENCE/'brect/fixed.py'):hashlib.sha256((ref.REFERENCE/'brect/fixed.py').read_bytes()).hexdigest()}},indent=2)+'\n')
print('PASS independent image fixtures5 +print page;2 positive,3 negative; exact B integer solver audit and25 grid probes each <1.5source pixels')
for r in records:print(r['name'],r['valid'],r['corners96_hex'])
