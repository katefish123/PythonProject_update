"""Native 1920x1080 black-marker scenes; three distinct frames prevent stale-cache aliases."""
import argparse,json,sys
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFont
def exact_image(image,points,ow,oh):
 from brect.fixed import solve_fixed,map_fixed,sample_fixed
 h=solve_fixed(points,ow,oh,image.shape[1],image.shape[0]);yy,xx=np.mgrid[:oh,:ow].astype(np.int64)
 den=h[6]*xx+h[7]*yy+h[8];nx=h[0]*xx+h[1]*yy+h[2];ny=h[3]*xx+h[4]*yy+h[5]
 assert (den>2**20).all() and (nx>=0).all() and (ny>=0).all()
 qx,qy=nx*256//den,ny*256//den;x0=qx>>8;y0=qy>>8
 x1=np.minimum(x0+1,image.shape[1]-1);y1=np.minimum(y0+1,image.shape[0]-1)
 fx=(qx&255)[...,None];fy=(qy&255)[...,None];p=image.astype(np.int64)
 result=((p[y0,x0]*(256-fx)*(256-fy)+p[y0,x1]*fx*(256-fy)+p[y1,x0]*(256-fx)*fy+p[y1,x1]*fx*fy)>>16).astype(np.uint8)
 rng=np.random.default_rng(20261014)
 for index in np.r_[0,ow-1,ow*(oh-1),ow*oh-1,rng.integers(ow*oh,size=500)]:
  x,y=int(index%ow),int(index//ow);sx,sy,valid=map_fixed(h,x,y);assert valid
  np.testing.assert_array_equal(result[y,x],sample_fixed(image,sx,sy,'bilinear'))
 return result,h
def main():
 p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--config',required=True);a=p.parse_args()
 root=a.output/'fullhd_tests';config=json.loads(a.config);sys.path.insert(0,str(root/'reference'))
 from brect.golden import detect_markers,homography
 sw,sh=config['source'];ow,oh=config['output'];points=config['fixture_points']
 doc=Image.new('RGB',(ow,oh),'white');draw=ImageDraw.Draw(doc)
 font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',34)
 draw.text((70,100),'NATIVE FULL HD / BLACK MARKERS',font=font,fill='black')
 for y in range(260,780,52):draw.line((90,y,550,y),fill='#606060',width=2)
 for x in range(90,551,46):draw.line((x,260,x,780),fill='#808080',width=2)
 draw.ellipse((220,400,420,600),outline='#303030',width=5)
 draw.rectangle((240,630,300,690),fill='#d62828');draw.rectangle((310,630,370,690),fill='#2872d6')
 radius=config['fixture_marker_radius']
 records=[];corner_words=[]
 shifts=[[(0,0)]*4,[(6,-4),(-6,4),(-8,-6),(8,6)],[(12,-8),(-12,8),(-14,-10),(14,10)]]
 yy,xx=np.mgrid[:sh,:sw];paper=np.asarray(doc)
 for kind,suffix in [(0,''),(1,'variant_'),(2,'variant2_')]:
  frame_points=[[x+dx,y+dy] for (x,y),(dx,dy) in zip(points,shifts[kind])]
  forward=np.linalg.inv(homography(frame_points,ow,oh))
  uvw=forward@np.stack([xx.ravel(),yy.ravel(),np.ones(xx.size)]);u,v=uvw[:2]/uvw[2]
  inside=(u>=0)&(u<=ow-1)&(v>=0)&(v<=oh-1);pixels=np.full((sw*sh,3),180,np.uint8)
  pixels[inside]=paper[np.floor(v[inside]+.5).astype(int),np.floor(u[inside]+.5).astype(int)];source=pixels.reshape(sh,sw,3)
  for x,y in frame_points:source[y-radius:y+radius+1,x-radius:x+radius+1]=0
  image=source.copy();gray=(image[...,0]==image[...,1])&(image[...,1]==image[...,2])&(image[...,0]>64)&(image[...,0]<=220)
  image[gray]=image[gray]+16*kind
  found,stats=detect_markers(image,thresholds={'black':config['black']},rois=config['rois'],min_pixels=config['min_pixels'],max_pixels=config['max_pixels'],max_span=config['max_span'])
  np.testing.assert_array_equal(found,frame_points);expected,h=exact_image(image,found,ow,oh)
  corner_words.append(''.join(f'{int(value):03x}' for value in found.reshape(-1)))
  for name,data in [('source_'+suffix+'1920x1080',image),('expected_'+suffix+'640x904',expected)]:
   Image.fromarray(data).save(root/(name+'.png'));packed=(data[...,0].astype(np.uint32)<<16)|(data[...,1].astype(np.uint32)<<8)|data[...,2]
   np.savetxt(root/(name+'.hex'),packed.reshape(-1),fmt='%06x')
  records.append(dict(kind=kind,points=found.tolist(),statistics=stats,H_q=h,scalar_checks=504))
 assert len(set(corner_words))==3 and len({tuple(r['H_q']) for r in records})==3
 (root/'source_corners96.hex').write_text('\n'.join(corner_words)+'\n')
 (root/'fixture.json').write_text(json.dumps(dict(configuration=config,frames=records,synthetic=True,source_size=[sw,sh],hardware_accepted=False),indent=2)+'\n')
 print('NATIVE_BLACK_FIXTURE_READY source_pixels=2073600 result_pixels=578560 distinct_frames=3 scalar_checks=1512')
if __name__=='__main__':main()
